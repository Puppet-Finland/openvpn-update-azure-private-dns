#!/bin/sh
#
# Update an Azure Private DNS to include the VPN clients VPN IP. This is
# particularly useful with Azure VPN Gateway which does not support static IP
# addresses for VPN client.
#
# This script is meant to be run as both OpenVPN "up" and "down" script.
# However, it is generic enough to be used outside of OpenVPN as well.  By
# providing the record set name (-r) and IPv4 address (-4) you can use it as a
# generic Azure Private DNS A record updating script.
#
# By default the record set name is taken from the output of the "hostname"
# command. Similarly the IPv4 address is, by default, taken from the
# environment variable ifconfig_local that OpenVPN passes to the scripts it
# runs and which contains the VPN clients IPv4 VPN IP.

# Fail on any error
set -e

usage() {
    echo "Usage: $0 -a <up|down> -u <sp user> -p <sp pass> -t <tenant> -g <resource group> -z <zone> [-r <record set name>] [-4 <ipv4 address>]"
    exit 1
}

while getopts "a:u:p:t:g:z:r:4:h" o; do
    case "${o}" in
	a)  ACTION=${OPTARG}
	    ;;
        u)
            SP_USER=${OPTARG}
            ;;
        p)
            SP_PASS=${OPTARG}
            ;;
        t)
            TENANT=${OPTARG}
            ;;
        g)
            RG=${OPTARG}
            ;;
        z)
            ZONE_NAME=${OPTARG}
            ;;
        r)
            RECORD_SET_NAME=${OPTARG}
            ;;
        4)
            IPV4_ADDRESS=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# If selinux is enabled then writing to /root/.azure will fail due to label
# mismatch. So, use a custom Azure CLI configuration directory the openvpn
# process has write access to.
export AZURE_CONFIG_DIR="/etc/openvpn/scripts/.azure_update-azure-private-dns"

# Validate parameters
if [ -z "${ACTION}" ] || [ -z "${SP_USER}" ] || [ -z "${SP_PASS}" ] || [ -z "${TENANT}" ] || [ -z "${RG}" ] || [ -z "${ZONE_NAME}" ]; then
    usage
fi

# Validate the action parameter
echo "${ACTION}"|grep -E '^(up|down)$' > /dev/null 2>&1
if [ $? -ne 0 ]; then
    usage
fi

# Ensure that and IPv4 address is defined. If not, assumed this script is
# running from within an OpenVPN "up" script and set the VPN IP address
# automatically.
if [ "${IPV4_ADDRESS}" = "" ]; then
    if [ "${ifconfig_local}" = "" ]; then
        echo "ERROR: unable to determine the VPN IP address"
	exit 1
    else
        IPV4_ADDRESS=$ifconfig_local
    fi
fi

# Default to using hostname as the record name
if [ -z "${RECORD_SET_NAME}" ]; then
    RECORD_SET_NAME=$(hostname)
fi

# Login to Azure using the service principal
az login --service-principal -u "${SP_USER}" -p "${SP_PASS}" --tenant "${TENANT}" > /dev/null 2>&1

# Do not fail if the DNS record is missing
set +e
az network private-dns record-set a show --resource-group $RG --zone-name "${ZONE_NAME}" --name "${RECORD_SET_NAME}" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    EXISTS="true"
else
    EXISTS="false"
fi

set -e

if [ "${ACTION}" = "up" ]; then
    if [ "${EXISTS}" = "true" ]; then
        echo "WARNING: A record ${RECORD_SET_NAME}.${ZONE_NAME} will be overwritten with new data!"
        az network private-dns record-set a delete --yes --resource-group "${RG}" --zone-name "${ZONE_NAME}" --name "${RECORD_SET_NAME}" > /dev/null 2>&1
        echo "${RECORD_SET_NAME}.${ZONE_NAME} -> null"
    fi

    # Some versions of "az cli" require creating an empty A record first.
    az network private-dns record-set a create --resource-group "${RG}" --zone-name "${ZONE_NAME}" --name "${RECORD_SET_NAME}" > /dev/null 2>&1

    az network private-dns record-set a add-record --resource-group "${RG}" --zone-name "${ZONE_NAME}" --ipv4-address "${IPV4_ADDRESS}" --record-set-name "${RECORD_SET_NAME}" > /dev/null 2>&1

    echo "${RECORD_SET_NAME}.${ZONE_NAME} -> ${IPV4_ADDRESS}"

elif [ "${ACTION}" = "down" ]; then
    if [ "${EXISTS}" = "true" ]; then
        az network private-dns record-set a delete --yes --resource-group "${RG}" --zone-name "${ZONE_NAME}" --name "${RECORD_SET_NAME}" > /dev/null 2>&1
        echo "${RECORD_SET_NAME}.${ZONE_NAME} -> null"
    fi
fi
