# Azure DevOps CI/CD Reference

## Pipeline Architecture

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│   Code   │───▶│  Build   │───▶│  Stage   │───▶│  Prod    │
│  Commit  │    │ + Test   │    │  Deploy  │    │  Swap    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     │               │               │               │
  PR trigger    Lint, test,     Deploy to         Manual
  or merge      build image,    staging slot      approval
                push to ACR                       → slot swap
```

---

## Azure DevOps Pipelines (YAML)

### Full Pipeline: Build → Test → Deploy Staging → Approve → Swap to Production

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main
      - release/*
  paths:
    exclude:
      - '*.md'
      - docs/

pr:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: myapp-common              # Variable group (shared across stages)
  - name: containerRegistry
    value: 'myappregistry.azurecr.io'
  - name: imageName
    value: 'myapp-api'
  - name: tag
    value: '$(Build.BuildId)'

stages:
  # ═══════════════════════════════════════
  # Stage 1: Build & Test
  # ═══════════════════════════════════════
  - stage: Build
    displayName: 'Build & Test'
    jobs:
      - job: BuildAndTest
        displayName: 'Lint, Test, Build Image'
        steps:
          # Checkout
          - checkout: self
            fetchDepth: 1

          # Setup Node.js
          - task: NodeTool@0
            inputs:
              versionSpec: '22.x'
            displayName: 'Install Node.js'

          # Install dependencies
          - script: |
              corepack enable
              pnpm install --frozen-lockfile
            displayName: 'Install dependencies'

          # Lint
          - script: pnpm lint
            displayName: 'Lint'

          # Type check
          - script: pnpm typecheck
            displayName: 'Type check'

          # Unit & integration tests
          - script: pnpm test -- --coverage
            displayName: 'Run tests'

          # Publish test results
          - task: PublishTestResults@2
            inputs:
              testResultsFormat: 'JUnit'
              testResultsFiles: '**/junit.xml'
            condition: always()

          # Publish coverage
          - task: PublishCodeCoverageResults@2
            inputs:
              summaryFileLocation: 'coverage/cobertura-coverage.xml'
            condition: always()

          # Build Docker image
          - task: Docker@2
            displayName: 'Build Docker image'
            inputs:
              containerRegistry: 'AzureContainerRegistry'
              repository: '$(imageName)'
              command: 'build'
              Dockerfile: 'Dockerfile'
              tags: |
                $(tag)
                latest

          # Push to ACR
          - task: Docker@2
            displayName: 'Push to ACR'
            inputs:
              containerRegistry: 'AzureContainerRegistry'
              repository: '$(imageName)'
              command: 'push'
              tags: |
                $(tag)
                latest
            condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))

  # ═══════════════════════════════════════
  # Stage 2: Deploy to Staging
  # ═══════════════════════════════════════
  - stage: DeployStaging
    displayName: 'Deploy to Staging'
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployStaging
        displayName: 'Deploy to Staging Slot'
        environment: 'staging'
        strategy:
          runOnce:
            deploy:
              steps:
                # Run database migrations
                - script: |
                    az webapp config container set \
                      --name myapp-prod-api \
                      --resource-group myapp-prod-rg \
                      --slot staging \
                      --container-image-name $(containerRegistry)/$(imageName):$(tag)
                  displayName: 'Update staging container'

                # Wait for staging to be healthy
                - script: |
                    for i in $(seq 1 30); do
                      STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://myapp-prod-api-staging.azurewebsites.net/health)
                      if [ "$STATUS" = "200" ]; then
                        echo "Staging is healthy"
                        exit 0
                      fi
                      echo "Attempt $i: status $STATUS, waiting..."
                      sleep 10
                    done
                    echo "Staging health check failed"
                    exit 1
                  displayName: 'Health check staging'

                # Run smoke tests against staging
                - script: |
                    pnpm test:e2e --base-url https://myapp-prod-api-staging.azurewebsites.net
                  displayName: 'Smoke tests on staging'

  # ═══════════════════════════════════════
  # Stage 3: Swap to Production
  # ═══════════════════════════════════════
  - stage: DeployProduction
    displayName: 'Swap to Production'
    dependsOn: DeployStaging
    jobs:
      - deployment: SwapProduction
        displayName: 'Swap Staging → Production'
        environment: 'production'           # Requires manual approval (configured in Azure DevOps)
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureAppServiceManage@0
                  displayName: 'Swap slots'
                  inputs:
                    azureSubscription: 'AzureServiceConnection'
                    Action: 'Swap Slots'
                    WebAppName: 'myapp-prod-api'
                    ResourceGroupName: 'myapp-prod-rg'
                    SourceSlot: 'staging'

                # Verify production health after swap
                - script: |
                    sleep 15
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://myapp-prod-api.azurewebsites.net/health)
                    if [ "$STATUS" != "200" ]; then
                      echo "PRODUCTION HEALTH CHECK FAILED — initiating rollback"
                      az webapp deployment slot swap \
                        --name myapp-prod-api \
                        --resource-group myapp-prod-rg \
                        --slot production \
                        --target-slot staging
                      exit 1
                    fi
                    echo "Production is healthy"
                  displayName: 'Verify production + auto-rollback'
```

---

## Environment Approvals

Configure in Azure DevOps → Pipelines → Environments:

1. **staging** — auto-deploy on main branch merge
2. **production** — manual approval required (add specific approvers: tech lead, DevOps)
3. **Approval timeout:** 24 hours (deploy expires if not approved)

---

## Infrastructure Deployment Pipeline (Bicep)

```yaml
# infra-pipeline.yml — deploys Azure infrastructure changes
trigger:
  branches:
    include: [main]
  paths:
    include: [infra/*]

stages:
  - stage: ValidateInfra
    displayName: 'Validate Infrastructure'
    jobs:
      - job: Validate
        steps:
          - task: AzureCLI@2
            displayName: 'Validate Bicep'
            inputs:
              azureSubscription: 'AzureServiceConnection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az deployment group validate \
                  --resource-group myapp-prod-rg \
                  --template-file infra/main.bicep \
                  --parameters infra/parameters/prod.bicepparam

          - task: AzureCLI@2
            displayName: 'What-if (preview changes)'
            inputs:
              azureSubscription: 'AzureServiceConnection'
              scriptType: 'bash'
              inlineScript: |
                az deployment group what-if \
                  --resource-group myapp-prod-rg \
                  --template-file infra/main.bicep \
                  --parameters infra/parameters/prod.bicepparam

  - stage: DeployInfra
    displayName: 'Deploy Infrastructure'
    dependsOn: ValidateInfra
    jobs:
      - deployment: DeployBicep
        environment: 'production'    # Manual approval
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  displayName: 'Deploy Bicep'
                  inputs:
                    azureSubscription: 'AzureServiceConnection'
                    scriptType: 'bash'
                    inlineScript: |
                      az deployment group create \
                        --resource-group myapp-prod-rg \
                        --template-file infra/main.bicep \
                        --parameters infra/parameters/prod.bicepparam
```

---

## Database Migrations in Pipeline

```yaml
# Run migrations BEFORE deploying new app version
- script: |
    # Option A: Run migration command via App Service SSH
    az webapp ssh --name myapp-prod-api --resource-group myapp-prod-rg --slot staging \
      --command "npx prisma migrate deploy"

    # Option B: Run migration from pipeline agent (needs DB network access)
    # DATABASE_URL must be available as pipeline secret
    npx prisma migrate deploy
  displayName: 'Run database migrations'
  env:
    DATABASE_URL: $(DATABASE_URL)
```

### Migration Safety Rules
1. **Migrations must be backward-compatible.** The old app version must work with the new schema.
2. **Never drop columns in the same deploy as code that removes their usage.** Split into two deploys.
3. **Add columns as nullable first.** Make them required in a subsequent deploy after backfill.
4. **Test migrations against a staging database copy** before production.

---

## Azure Container Registry (ACR)

```bash
# Create ACR
az acr create --name myappregistry --resource-group $RG --sku Standard --admin-enabled false

# Grant App Service access to pull images
az role assignment create \
  --assignee $(az webapp identity show --name $APP --resource-group $RG --query principalId -o tsv) \
  --role AcrPull \
  --scope $(az acr show --name myappregistry --query id -o tsv)

# Build and push image (from local or CI)
az acr build --registry myappregistry --image myapp-api:latest --file Dockerfile .
```

---

## Variable Groups & Secrets

```yaml
# Reference a variable group (defined in Azure DevOps → Library)
variables:
  - group: myapp-prod-secrets    # Contains: DATABASE_URL, STRIPE_KEY, etc.

# Reference Azure Key Vault secrets (auto-mapped to pipeline variables)
variables:
  - group: myapp-keyvault-secrets  # Linked to Key Vault in Azure DevOps Library
```

### Setting Up Key Vault-Linked Variable Group

1. Azure DevOps → Pipelines → Library → + Variable group
2. Toggle "Link secrets from an Azure key vault as variables"
3. Select subscription → Key Vault
4. Authorize → Select secrets to expose
5. Reference in pipeline with `$(secret-name)`

---

## GitHub Repos Integration with Azure DevOps

If code lives in GitHub but CI/CD runs in Azure DevOps:

```yaml
resources:
  repositories:
    - repository: app
      type: github
      name: 'your-org/your-repo'
      endpoint: 'GitHubServiceConnection'

trigger:
  - main

pool:
  vmImage: 'ubuntu-latest'

steps:
  - checkout: app
  # ... rest of pipeline
```

---

## Checklist

- [ ] Pipeline triggers on main branch merge (not manual)
- [ ] PR builds run lint + test (no deploy)
- [ ] Docker images tagged with build ID (not just `latest`)
- [ ] Staging deployment with health check gate
- [ ] Production requires manual approval
- [ ] Auto-rollback if production health check fails after swap
- [ ] Database migrations backward-compatible and run before app deploy
- [ ] Secrets from Key Vault variable group (never hardcoded)
- [ ] Infrastructure changes via Bicep with what-if preview
- [ ] Pipeline caches dependencies (pnpm store, Docker layers)
