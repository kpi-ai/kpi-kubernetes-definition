@description('Location for all resources')
param location string = 'East US'

@description('Name of the Resource Group')
param resourceGroupName string = 'Development'

@description('Virtual Network Name')
param vnetName string = 'kpi-network'

@description('AKS Subnet Name')
param aksSubnetName string = 'kpi-subnet'

@description('Gateway Subnet Name')
param gatewaySubnetName string = 'GatewaySubnet'

@description('Virtual Network Address Prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet Address Prefix')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('Gateway Subnet Address Prefix')
param gatewaySubnetAddressPrefix string = '10.0.2.0/27'

@description('AKS Cluster Name')
param aksClusterName string = 'kpi'

@description('Microsoft Entra ID Admin Group Object ID')
param adminGroupObjectId string = '2766200e-d25a-4b1d-94fa-0d846fe0e527'

@description('Microsoft Entra ID Tenant ID')
param tenantId string = '29b83a3f-33a4-45f1-b783-03d9ac08df31'

@description('SSH Public Key for AKS Nodes')
param sshPublicKey string

@description('VPN Gateway Name')
param vpnGatewayName string = 'kpi-gateway'

@description('VPN Gateway SKU')
param vpnGatewaySku string = 'VpnGw2AZ'

@description('VPN Gateway Generation')
param vpnGatewayGeneration string = 'Generation2'

@description('Service CIDR for Kubernetes Services')
param serviceCidr string = '10.0.3.0/24' // Updated to avoid conflict

@description('DNS Service IP for Kubernetes')
param dnsServiceIP string = '10.0.3.10' // Ensure this is within the new service CIDR

@description('Availability Zone for Public IP')
param publicIPZone string = '1' // Specify the zone for the Public IP. You can change this to '1', '2', or '3'


// Create Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
      {
        name: gatewaySubnetName
        properties: {
          addressPrefix: gatewaySubnetAddressPrefix
        }
      }
    ]
  }
}

// Subnet for AKS
resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-08-01' existing = {
  parent: vnet
  name: aksSubnetName
}

// Subnet for VPN Gateway
resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2021-08-01' existing = {
  parent: vnet
  name: gatewaySubnetName
}

// Create Public IP for VPN Gateway
resource vpnPublicIP 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: '${vpnGatewayName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'  // Specify the availability zone for the Public IP
  ]
}

// Create VPN Gateway
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2021-08-01' = {
  name: vpnGatewayName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'vpngatewayconfig'
        properties: {
          publicIPAddress: {
            id: vpnPublicIP.id
          }
          subnet: {
            id: gatewaySubnet.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    sku: {
      name: vpnGatewaySku
      tier: vpnGatewaySku
    }
    vpnGatewayGeneration: vpnGatewayGeneration
  }
}

// Create AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-01-01' = {
  name: aksClusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.29.4'  // or use 'default' for the latest stable version
    dnsPrefix: '${aksClusterName}-dns'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        mode: 'System'
        count: 1
        vmSize: 'Standard_DS2_v2'
        minCount: 1
        maxCount: 5
        osType: 'Linux'
        vnetSubnetID: aksSubnet.id
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
      }
      {
        name: 'userpool'
        mode: 'User'
        count: 1
        vmSize: 'Standard_DS2_v2'
        minCount: 1
        maxCount: 5
        osType: 'Linux'
        vnetSubnetID: aksSubnet.id
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
      }
      {
        name: 'ml'
        mode: 'User'
        count: 1
        vmSize: 'Standard_DS3_v2'
        minCount: 1
        maxCount: 5
        osType: 'Linux'
        vnetSubnetID: aksSubnet.id
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      dockerBridgeCidr: '172.17.0.1/16'
    }
    apiServerAccessProfile: {
      enablePrivateCluster: true
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: [
        adminGroupObjectId
      ]
      tenantID: tenantId
    }
    linuxProfile: {
      adminUsername: 'azureuser'
      ssh: {
        publicKeys: [
          {
            keyData: sshPublicKey
          }
        ]
      }
    }
  }
  tags: {
    Environment: 'Development'
  }
}

// Outputs
output aksClusterName string = aksCluster.name
output vpnGatewayName string = vpnGateway.name
output vpnGatewayPublicIP string = vpnPublicIP.properties.ipAddress
output virtualNetworkName string = vnet.name
output aksSubnetId string = aksSubnet.id
output gatewaySubnetId string = gatewaySubnet.id
