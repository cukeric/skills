# Azure Cloud Deployment Reference

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Azure Front Door                      │
│              (Global CDN + WAF + SSL)                    │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│                   Virtual Network                        │
│  ┌─────────────────┐  ┌──────────────────────────────┐  │
│  │  App Service     │  │  Private Endpoints            │  │
│  │  (or Container   │  │  ┌─────────┐ ┌────────────┐ │  │
│  │   Apps / AKS)    │──│──│ Postgres │ │   Redis    │ │  │
│  │                  │  │  └─────────┘ └────────────┘ │  │
│  │  Managed Identity│  │  ┌─────────┐ ┌────────────┐ │  │
│  │  → Key Vault     │  │  │ Storage │ │ Key Vault  │ │  │
│  └─────────────────┘  │  └─────────┘ └────────────┘ │  │
│                        └──────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Azure Monitor + App Insights + Log Analytics     │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## Azure App Service (Default Choice)

### When to Use
- Web apps, APIs, backend services
- Teams that want managed infrastructure (no Kubernetes overhead)
- Need deployment slots, auto-scale, custom domains out of the box
- Supports: Node.js, Python, .NET, Java, Docker containers

### Setup with Azure CLI

```bash
# Variables
RG="myapp-prod-rg"
LOCATION="eastus2"
PLAN="myapp-prod-plan"
APP="myapp-prod-api"

# Resource group
az group create --name $RG --location $LOCATION

# App Service Plan (Linux, P1v3 for production)
az appservice plan create \
  --name $PLAN \
  --resource-group $RG \
  --sku P1v3 \
  --is-linux

# App Service (Docker container)
az webapp create \
  --name $APP \
  --resource-group $RG \
  --plan $PLAN \
  --deployment-container-image-name myregistry.azurecr.io/myapp:latest

# Enable system-assigned Managed Identity
az webapp identity assign --name $APP --resource-group $RG

# Configure app settings (environment variables)
az webapp config appsettings set --name $APP --resource-group $RG --settings \
  NODE_ENV=production \
  DATABASE_URL="@Microsoft.KeyVault(SecretUri=https://myapp-kv.vault.azure.net/secrets/database-url/)" \
  REDIS_URL="@Microsoft.KeyVault(SecretUri=https://myapp-kv.vault.azure.net/secrets/redis-url/)"

# Enable HTTPS only
az webapp update --name $APP --resource-group $RG --https-only true

# Set minimum TLS version
az webapp config set --name $APP --resource-group $RG --min-tls-version 1.2

# Configure health check
az webapp config set --name $APP --resource-group $RG --generic-configurations '{"healthCheckPath": "/health"}'
```

### Deployment Slots (Zero-Downtime)

```bash
# Create staging slot
az webapp deployment slot create --name $APP --resource-group $RG --slot staging

# Deploy to staging
az webapp config container set --name $APP --resource-group $RG --slot staging \
  --container-image-name myregistry.azurecr.io/myapp:v2.0.0

# Test staging slot
curl https://myapp-prod-api-staging.azurewebsites.net/health

# Swap staging → production (instant, zero-downtime)
az webapp deployment slot swap --name $APP --resource-group $RG --slot staging --target-slot production

# If something is wrong — swap back
az webapp deployment slot swap --name $APP --resource-group $RG --slot production --target-slot staging
```

### Auto-Scale Rules

```bash
# Scale based on CPU percentage
az monitor autoscale create \
  --resource-group $RG \
  --resource $PLAN \
  --resource-type Microsoft.Web/serverFarms \
  --min-count 2 \
  --max-count 10 \
  --count 2

# Scale out when CPU > 70%
az monitor autoscale rule create \
  --resource-group $RG \
  --autoscale-name $PLAN-autoscale \
  --condition "Percentage CPU > 70 avg 5m" \
  --scale out 2

# Scale in when CPU < 30%
az monitor autoscale rule create \
  --resource-group $RG \
  --autoscale-name $PLAN-autoscale \
  --condition "Percentage CPU < 30 avg 10m" \
  --scale in 1
```

---

## Azure Container Apps (Serverless Containers)

### When to Use
- Containerized apps that need auto-scaling (including scale to zero)
- Microservices with Dapr integration
- Event-driven workloads (queue processors, scheduled tasks)
- Want container flexibility without Kubernetes complexity

### Setup

```bash
# Container Apps Environment
az containerapp env create \
  --name myapp-env \
  --resource-group $RG \
  --location $LOCATION \
  --logs-workspace-id $LOG_ANALYTICS_ID

# Deploy container app
az containerapp create \
  --name myapp-api \
  --resource-group $RG \
  --environment myapp-env \
  --image myregistry.azurecr.io/myapp:latest \
  --registry-server myregistry.azurecr.io \
  --registry-identity system \
  --target-port 3000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 10 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars \
    NODE_ENV=production \
    DATABASE_URL=secretref:database-url \
  --secrets \
    database-url=keyvaultref:https://myapp-kv.vault.azure.net/secrets/database-url,identityref:system

# Scale rules (HTTP concurrent requests)
az containerapp update --name myapp-api --resource-group $RG \
  --scale-rule-name http-rule \
  --scale-rule-type http \
  --scale-rule-http-concurrency 50
```

---

## Azure Kubernetes Service (AKS)

### When to Use
- Complex microservice architectures (10+ services)
- Teams with Kubernetes expertise
- Need full control over networking, scheduling, service mesh
- Multi-team organizations with namespace isolation

### Setup

```bash
# Create AKS cluster
az aks create \
  --resource-group $RG \
  --name myapp-aks \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --network-plugin azure \
  --vnet-subnet-id $SUBNET_ID \
  --enable-addons monitoring \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group $RG --name myapp-aks

# Deploy with kubectl / Helm
kubectl apply -f k8s/
```

### Kubernetes Manifests Pattern

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-api
  labels:
    app: myapp-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp-api
  template:
    metadata:
      labels:
        app: myapp-api
    spec:
      serviceAccountName: myapp-api
      containers:
        - name: api
          image: myregistry.azurecr.io/myapp:latest
          ports:
            - containerPort: 3000
          env:
            - name: NODE_ENV
              value: "production"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets
                  key: database-url
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /readyz
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp-api
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Azure Front Door (CDN + WAF + Global Load Balancing)

### Setup

```bash
az afd profile create --profile-name myapp-fd --resource-group $RG --sku Premium_AzureFrontDoor

# Add endpoint
az afd endpoint create --endpoint-name myapp --profile-name myapp-fd --resource-group $RG

# Origin group (backend pool)
az afd origin-group create \
  --origin-group-name myapp-api-origin \
  --profile-name myapp-fd \
  --resource-group $RG \
  --probe-request-type GET \
  --probe-path /health \
  --probe-protocol Https \
  --probe-interval-in-seconds 30

# Add origin (App Service)
az afd origin create \
  --origin-name myapp-api \
  --origin-group-name myapp-api-origin \
  --profile-name myapp-fd \
  --resource-group $RG \
  --host-name myapp-prod-api.azurewebsites.net \
  --origin-host-header myapp-prod-api.azurewebsites.net \
  --http-port 80 \
  --https-port 443 \
  --priority 1

# WAF policy
az network front-door waf-policy create \
  --name myappWAF \
  --resource-group $RG \
  --sku Premium_AzureFrontDoor \
  --mode Prevention
```

---

## Networking: Virtual Networks & Private Endpoints

### Why Private Endpoints
By default, Azure PaaS services (PostgreSQL, Redis, Storage) are accessible from the internet. Private Endpoints move them inside your VNet — traffic never leaves Azure's backbone.

```bash
# Create VNet with subnets
az network vnet create --name myapp-vnet --resource-group $RG --address-prefixes 10.0.0.0/16
az network vnet subnet create --name app-subnet --vnet-name myapp-vnet --resource-group $RG --address-prefixes 10.0.1.0/24
az network vnet subnet create --name db-subnet --vnet-name myapp-vnet --resource-group $RG --address-prefixes 10.0.2.0/24
az network vnet subnet create --name redis-subnet --vnet-name myapp-vnet --resource-group $RG --address-prefixes 10.0.3.0/24

# VNet integration for App Service
az webapp vnet-integration add --name $APP --resource-group $RG --vnet myapp-vnet --subnet app-subnet

# Private Endpoint for PostgreSQL
az network private-endpoint create \
  --name myapp-db-pe \
  --resource-group $RG \
  --vnet-name myapp-vnet \
  --subnet db-subnet \
  --private-connection-resource-id $POSTGRES_ID \
  --group-id postgresqlServer \
  --connection-name myapp-db-connection

# Private DNS zone (resolves private endpoint hostname)
az network private-dns zone create --name privatelink.postgres.database.azure.com --resource-group $RG
az network private-dns link vnet create --zone-name privatelink.postgres.database.azure.com --resource-group $RG --virtual-network myapp-vnet --name myapp-dns-link --registration-enabled false
```

---

## Azure Key Vault + Managed Identity

### Zero-Credential Secret Access

```bash
# Create Key Vault
az keyvault create --name myapp-kv --resource-group $RG --location $LOCATION --sku standard

# Add secrets
az keyvault secret set --vault-name myapp-kv --name database-url --value "postgresql://..."
az keyvault secret set --vault-name myapp-kv --name redis-url --value "rediss://..."
az keyvault secret set --vault-name myapp-kv --name stripe-secret-key --value "sk_live_..."

# Grant App Service Managed Identity access to Key Vault
IDENTITY_ID=$(az webapp identity show --name $APP --resource-group $RG --query principalId -o tsv)
az keyvault set-policy --name myapp-kv --object-id $IDENTITY_ID --secret-permissions get list

# App Service reads secrets via Key Vault references (no code changes needed)
# In app settings: @Microsoft.KeyVault(SecretUri=https://myapp-kv.vault.azure.net/secrets/database-url/)
```

### Accessing Key Vault from Application Code

```typescript
// When Key Vault references aren't sufficient (e.g., dynamic secret rotation)
import { DefaultAzureCredential } from '@azure/identity'
import { SecretClient } from '@azure/keyvault-secrets'

const credential = new DefaultAzureCredential()  // Uses Managed Identity automatically
const client = new SecretClient('https://myapp-kv.vault.azure.net', credential)

async function getSecret(name: string): Promise<string> {
  const secret = await client.getSecret(name)
  return secret.value!
}
```

---

## Bicep Infrastructure-as-Code

### Main Template

```bicep
// infra/main.bicep
targetScope = 'resourceGroup'

@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region')
param location string = resourceGroup().location

@description('App Service base name')
param appName string = 'myapp'

var prefix = '${appName}-${environment}'

// Modules
module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: { prefix: prefix, location: location }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVault'
  params: { prefix: prefix, location: location }
}

module database 'modules/database.bicep' = {
  name: 'database'
  params: {
    prefix: prefix, location: location
    subnetId: networking.outputs.dbSubnetId
    keyVaultName: keyVault.outputs.name
  }
}

module redis 'modules/redis.bicep' = {
  name: 'redis'
  params: {
    prefix: prefix, location: location
    subnetId: networking.outputs.redisSubnetId
  }
}

module appService 'modules/app-service.bicep' = {
  name: 'appService'
  params: {
    prefix: prefix, location: location
    subnetId: networking.outputs.appSubnetId
    keyVaultName: keyVault.outputs.name
    appInsightsConnectionString: monitoring.outputs.connectionString
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: { prefix: prefix, location: location }
}

output appServiceUrl string = appService.outputs.defaultHostName
output keyVaultName string = keyVault.outputs.name
```

### Deploy

```bash
# Deploy to dev
az deployment group create \
  --resource-group myapp-dev-rg \
  --template-file infra/main.bicep \
  --parameters infra/parameters/dev.bicepparam

# Deploy to production
az deployment group create \
  --resource-group myapp-prod-rg \
  --template-file infra/main.bicep \
  --parameters infra/parameters/prod.bicepparam
```

---

## Security Checklist (Azure)

- [ ] Managed Identity enabled (no stored credentials)
- [ ] Key Vault used for all secrets (Key Vault references in App Settings)
- [ ] VNet integration enabled for App Service / Container Apps
- [ ] Private Endpoints for PostgreSQL, Redis, Storage (no public access)
- [ ] NSGs restrict traffic between subnets
- [ ] Front Door WAF in Prevention mode
- [ ] HTTPS-only enforced, TLS 1.2 minimum
- [ ] Diagnostic settings enabled (logs → Log Analytics)
- [ ] Azure Defender enabled for containers and databases
- [ ] Deployment slots used for zero-downtime releases
- [ ] RBAC: principle of least privilege for all Azure AD service principals
- [ ] Resource locks on production resource group (prevent accidental deletion)
