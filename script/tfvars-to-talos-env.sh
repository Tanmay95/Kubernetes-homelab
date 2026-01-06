#!/bin/bash

# tfvars-to-talos-env.sh
# Extract values from cluster.auto.tfvars and generate talenv.yaml for talhelper

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[USAGE]${NC} $1"
}

TFVARS_FILE="$SCRIPT_DIR/../cluster.auto.tfvars"
OUTPUT_FILE="$SCRIPT_DIR/talenv.yaml"
OUTPUT_FORMAT="yaml"
VERBOSE=false

SUMMARY_NODE_COUNT=0
SUMMARY_TOTAL_RAM_GB=0
SUMMARY_TOTAL_DISK_GB=0
SUMMARY_NODES_SPECS=""

# Show usage
usage() {
    cat << EOF
tfvars-to-talos-env - Extract Terraform values for Talos talenv.yaml

USAGE:
    $0 [OPTIONS] [TFVARS_FILE]

OPTIONS:
    -h, --help              Show this help message
    -o, --output FILE       Output to file (default: script/talenv.yaml)
    -f, --format FORMAT     Output format: yaml|shell (default: yaml)
    -v, --verbose          Enable verbose output

EXAMPLES:
    # Generate talenv.yaml for talhelper
    $0

    # Generate shell exports (legacy)
    $0 -f shell

    # Use with talhelper
    $0 && talhelper genconfig --env-file talenv.yaml

EOF
}

extract_tfvar_string() {
    local key="$1"
    local file="$2"
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

compute_cluster_summary() {
    local file="$1"

    SUMMARY_NODE_COUNT=0
    SUMMARY_TOTAL_RAM_GB=0
    SUMMARY_TOTAL_DISK_GB=0
    SUMMARY_NODES_SPECS=""

    local in_nodes_array=false
    local current_node=""
    while IFS= read -r line; do
        if [[ "$line" =~ nodes[[:space:]]*=[[:space:]]*\[ ]]; then
            in_nodes_array=true
            continue
        fi
        if [[ "$in_nodes_array" == true && "$line" =~ ^[[:space:]]*\][[:space:]]*$ ]]; then
            break
        fi
        if [[ "$in_nodes_array" == true ]]; then
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            current_node+="$line "
            if [[ "$line" =~ \}[[:space:]]*,?[[:space:]]*$ ]]; then
                local name role memory_mib disk_gb
                name=$(echo "$current_node" | sed -n 's/.*name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
                role=$(echo "$current_node" | sed -n 's/.*role[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
                memory_mib=$(echo "$current_node" | sed -n 's/.*memory[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p')
                disk_gb=$(echo "$current_node" | sed -n 's/.*disk_size[[:space:]]*=[[:space:]]*"\([0-9][0-9]*\)G".*/\1/p')

                local ram_gb=0
                if [[ -n "${memory_mib}" ]]; then
                    ram_gb=$((memory_mib / 1024))
                    SUMMARY_TOTAL_RAM_GB=$((SUMMARY_TOTAL_RAM_GB + ram_gb))
                fi

                local disk_val=0
                if [[ -n "${disk_gb}" ]]; then
                    disk_val=$disk_gb
                    SUMMARY_TOTAL_DISK_GB=$((SUMMARY_TOTAL_DISK_GB + disk_val))
                fi

                if [[ -n "${name}" && -n "${role}" ]]; then
                    SUMMARY_NODES_SPECS+="$name ($role): ${ram_gb}GB RAM, ${disk_val}GB disk\n"
                fi

                SUMMARY_NODE_COUNT=$((SUMMARY_NODE_COUNT + 1))
                current_node=""
            fi
        fi
    done < "$file"
}

find_first_control_plane_ip() {
    local file="$1"
    local first_control_plane_ip=""
    local in_nodes_array_pre=false
    local current_node_pre=""
    while IFS= read -r line_pre; do
        if [[ "$line_pre" =~ nodes[[:space:]]*=[[:space:]]*\[ ]]; then
            in_nodes_array_pre=true
            continue
        fi
        if [[ "$in_nodes_array_pre" == true && "$line_pre" =~ ^[[:space:]]*\][[:space:]]*$ ]]; then
            break
        fi
        if [[ "$in_nodes_array_pre" == true ]]; then
            [[ -z "$line_pre" || "$line_pre" =~ ^[[:space:]]*# ]] && continue
            current_node_pre+="$line_pre "
            if [[ "$line_pre" =~ \}[[:space:]]*,?[[:space:]]*$ ]]; then
                local role_pre
                role_pre=$(echo "$current_node_pre" | sed -n 's/.*role[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
                if [[ "$role_pre" == "controlplane" ]]; then
                    first_control_plane_ip=$(echo "$current_node_pre" | sed -n 's/.*ip[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
                    if [[ -n "$first_control_plane_ip" ]]; then
                        echo "$first_control_plane_ip"
                        return 0
                    fi
                fi
                current_node_pre=""
            fi
        fi
    done < "$file"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            TFVARS_FILE="$1"
            shift
            ;;
    esac
done

# Check if tfvars file exists
if [[ ! -f "$TFVARS_FILE" ]]; then
    echo "Error: Terraform vars file '$TFVARS_FILE' not found" >&2
    exit 1
fi

if [[ "$VERBOSE" == true ]]; then
    print_info "Processing: $TFVARS_FILE"
fi

# Function to extract values and generate exports
generate_env_vars() {
    compute_cluster_summary "$TFVARS_FILE"
    local first_control_plane_ip
    first_control_plane_ip="$(find_first_control_plane_ip "$TFVARS_FILE")"

    if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
        echo "# Cluster Summary"
        echo "# Node count: $SUMMARY_NODE_COUNT"
        echo "# Total RAM: ${SUMMARY_TOTAL_RAM_GB}GB"
        echo "# Total Disk: ${SUMMARY_TOTAL_DISK_GB}GB"
        echo -e "# Node specs:\n$(echo -e "$SUMMARY_NODES_SPECS" | sed 's/^/# /')"
        echo "# Expected time: 3-15 minutes for VM creation (depends on disk speed and node count)"
        echo "# Requirements: Proxmox node with enough RAM/disk, storage supporting VM images (local-lvm)"
        echo "# talenv.yaml - Talos environment variables for talhelper"
        echo "# Extracted from $TFVARS_FILE"
        echo "# Generated on $(date)"
        echo ""
    else
        echo "# Talos environment variables extracted from $TFVARS_FILE"
        echo "# Generated on $(date)"
        echo ""
    fi
    
    local gateway_ip
    gateway_ip="$(extract_tfvar_string "network_gateway" "$TFVARS_FILE")"
    if [[ -z "$gateway_ip" ]]; then
        local network_base=""
        network_base=$(grep -oE 'ip[[:space:]]*=[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+"' "$TFVARS_FILE" | head -1 | sed -E 's/.*="([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+"/\1/')
        if [[ -n "$network_base" ]]; then
            gateway_ip="${network_base}.1"
        fi
    fi

    if [[ -n "$gateway_ip" ]]; then
        if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
            echo "# Network Configuration"
            echo "GATEWAY_IP: \"${gateway_ip}\""
            # For bootstrapping, use the first control plane IP.
            # For HA, you would use a VIP here.
            if [[ -n "$first_control_plane_ip" ]]; then
                echo "CONTROL_PLANE_ENDPOINT_IP: \"$first_control_plane_ip\""
            else
                echo "# WARNING: Could not determine first control plane IP. Using fallback." >&2
                echo "CONTROL_PLANE_ENDPOINT_IP: \"192.168.1.100\"" # Fallback
            fi
            echo ""
        else
            echo "# Network Configuration"
            echo "export GATEWAY_IP=\"${gateway_ip}\""
            if [[ -n "$first_control_plane_ip" ]]; then
                echo "export CONTROL_PLANE_ENDPOINT_IP=\"$first_control_plane_ip\""
            else
                echo "# WARNING: Could not determine first control plane IP. Using fallback." >&2
                echo "export CONTROL_PLANE_ENDPOINT_IP=\"192.168.1.100\""
            fi
            echo ""
        fi
    fi
    
    # Process each node in the nodes array
    local control_plane_idx=0
    local worker_idx=1  # Start workers at index 1
    local gpu_worker_idx=0
    
    if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
        echo "# Node Configuration"
    else
        echo "# Node Configuration"
    fi
    
    # Extract nodes array using a simpler bash approach
    local in_nodes_array=false
    local current_node=""
    
    while IFS= read -r line; do
        # Check if we're entering nodes array
        if [[ "$line" =~ nodes[[:space:]]*=[[:space:]]*\[ ]]; then
            in_nodes_array=true
            continue
        fi
        
        # Check if we're exiting nodes array  
        if [[ "$in_nodes_array" == true && "$line" =~ ^[[:space:]]*\][[:space:]]*$ ]]; then
            break
        fi
        
        # Process lines within nodes array
        if [[ "$in_nodes_array" == true ]]; then
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            
            # Accumulate the current node definition
            current_node+="$line "
            
            # Check if we have a complete node (ends with })
            if [[ "$line" =~ \}[[:space:]]*,?[[:space:]]*$ ]]; then
                # Extract values from the complete node string
                local name=$(echo "$current_node" | sed -n 's/.*name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
                local role=$(echo "$current_node" | sed -n 's/.*role[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')  
                local ip=$(echo "$current_node" | sed -n 's/.*ip[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p')
                
                # Output if we have required values
                if [[ -n "$name" && -n "$role" && -n "$ip" ]]; then
                    # Generate role-based environment variables
                    case "$role" in
                        "controlplane")
                            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                                echo "TALOS_CONTROL_PLANE_IP_${control_plane_idx}: \"$ip\""
                                echo "TALOS_CONTROL_PLANE_NAME_${control_plane_idx}: \"$name\""
                            else
                                echo "export TALOS_CONTROL_PLANE_IP_${control_plane_idx}=\"$ip\""
                                echo "export TALOS_CONTROL_PLANE_NAME_${control_plane_idx}=\"$name\""
                            fi
                            if [[ "$VERBOSE" == true ]]; then
                                print_info "Processed control plane ${control_plane_idx}: $name -> $ip" >&2
                            fi
                            ((control_plane_idx+=1))
                            ;;
                        "worker")
                            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                                echo "TALOS_WORKER_IP_${worker_idx}: \"$ip\""
                                echo "TALOS_WORKER_NAME_${worker_idx}: \"$name\""
                            else
                                echo "export TALOS_WORKER_IP_${worker_idx}=\"$ip\""
                                echo "export TALOS_WORKER_NAME_${worker_idx}=\"$name\""
                            fi
                            if [[ "$VERBOSE" == true ]]; then
                                print_info "Processed worker ${worker_idx}: $name -> $ip" >&2
                            fi
                            ((worker_idx+=1))
                            ;;
                        "worker-gpu")
                            if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
                                echo "TALOS_GPU_WORKER_IP_${gpu_worker_idx}: \"$ip\""
                                echo "TALOS_GPU_WORKER_NAME_${gpu_worker_idx}: \"$name\""
                            else
                                echo "export TALOS_GPU_WORKER_IP_${gpu_worker_idx}=\"$ip\""
                                echo "export TALOS_GPU_WORKER_NAME_${gpu_worker_idx}=\"$name\""
                            fi
                            if [[ "$VERBOSE" == true ]]; then
                                print_info "Processed GPU worker ${gpu_worker_idx}: $name -> $ip" >&2
                            fi
                            ((gpu_worker_idx+=1))
                            ;;
                        *)
                            if [[ "$VERBOSE" == true ]]; then
                                print_warning "Unknown role '$role' for node $name" >&2
                            fi
                            ;;
                    esac
                fi
                
                # Reset for next node
                current_node=""
            fi
        fi
    done < "$TFVARS_FILE"
    
    echo ""
    if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
        echo "# Usage with talhelper:"
        echo "# talhelper genconfig --env-file talenv.yaml"
    else
        echo "# Usage:"
        echo "# source <(./$(basename "$0") -f shell)"
        echo "# talhelper genconfig"
    fi
}

# Main execution
if [[ "$OUTPUT_FORMAT" == "yaml" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    generate_env_vars > "$OUTPUT_FILE"
    print_success "talenv.yaml generated: $OUTPUT_FILE"
    if [[ "$VERBOSE" == true ]]; then
        print_warning "Next steps:"
        echo "  cd talos && talhelper genconfig --env-file talenv.yaml"
    fi
else
    # Shell export format
    if [[ -n "$OUTPUT_FILE" ]]; then
        generate_env_vars > "$OUTPUT_FILE"
        print_success "Environment variables written to: $OUTPUT_FILE"
        print_warning "Source the file with: source $OUTPUT_FILE"
    else
        generate_env_vars
    fi
    
    if [[ "$VERBOSE" == true ]]; then
        print_success "Environment variables generated!"
        echo ""
        print_warning "Next steps:"
        echo "  1. Source the variables: source <($0 -f shell)"
        echo "  2. Run talhelper: talhelper genconfig"
        echo "  3. Or combine: source <($0 -f shell) && talhelper genconfig"
    fi
fi