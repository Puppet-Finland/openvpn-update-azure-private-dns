# openvpn-update-azure-private-dns

This repository contains a shell script that manages VPN client A records in an
Azure Private DNS zone automatically as VPN clients connect and disconnect.
This is particularly useful with the Azure VPN Gateway that does not hand out
static VPN IPs for OpenVPN clients.

# Prerequisites

In order for this script to work you need "az" command line tool:

* https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux

You also need to set up a service principal in your Azure AD and grant it a role that can edit Azure Private DNS. First login to your Azure tenant, for example:

    az login --tenant acme.onmicrosoft.com

Select the correct subscription from list:

    az account list

Set the correct subscription for the Azure CLI session, replacing the dummy
subscription ID with yours:

    az account set --subscription="00000000-0000-0000-0000-000000000000"

Create the service principal and attach it to the correct role:

    az ad sp create-for-rbac --role="Private DNS Zone Contributor" --scopes="/subscriptions/00000000-0000-0000-0000-000000000000"

If all went well, you will get something like this in return:

    {
      "appId": "01234567-89ab-cdef-0123-456789abcdef",
      "displayName": "azure-cli-2023-08-31-11-14-05",
      "password": "0FzPv9hzDFTwxVEy4SEsVrkp1b4L0SjVAKq6NTK-",
      "tenant": "abbababb-fafa-daab-4321-0123456789ab"
    }

You can now test logging in to Azure as this service principal:

    az login --service-principal -u <appId> -p <password> --tenant <tenant>

You should now be able to list private DNS zones like this:

    az network private-dns zone list

# Usage

Once everything is set you can add the script invocation to your OpenVPN
client configuration file:

```
script-security 2
setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
up "/etc/openvpn/scripts/update-azure-private-dns.sh -a up -u <appId> -p <password> -t <tenant-name> -g <resource-group-name> -z <private-dns-zone-name>"
up-restart
down "/etc/openvpn/scripts/update-azure-private-dns.sh -a down -u <appId> -p <password> -t <tenant-name> -g <resource-group-name> -z <private-dns-zone-name>"
down-pre
```

All the parameters - with the exception of *appId* and *password* are human-readable names - not random identifiers.

# Default behavior

The script defaults to using the output of *hostname* command as the A record
name. For example, if your Azure Private DNS zone name is
*internal.example.org*, *hostname* resolves to *mycomputer* and VPN IP is
*192.168.42.40*, the following DNS A record will be created:

* mycomputer.internal.example.org -> 192.168.42.40

Note that any existing A record with the same name will be wiped out. If you
want to avoid accidents you can force the hostname with the *-r* parameter
and make sure that OpenVPN client configuration permissions are locked down.

If you want to manually test the script (recommended) before integrating it
with OpenVPN you can use the *-4* parameter to pass an arbitrary IPv4 address
and the *-r* parameter to pass an arbitrary DNS record name.
