@description('The location used for all resources')
param location string = resourceGroup().location

@description('Name used for the deployment environment')
param environmentName string

@description('Unique suffix for naming resources')
param resourceToken string = uniqueString(resourceGroup().id, environmentName)

@description('Tags that will be applied to all resources')
param tags object = {
  'azd-env-name': environmentName
}

@description('Principal ID of the user running the deployment (for role assignments)')
param userPrincipalId string = ''

// ----------------------------------------------------
// App Service and configuration
// ----------------------------------------------------

@description('Name of the App Service for hosting the Blazor app')
param appServiceName string = 'app-${resourceToken}'

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v2'
  'P2v2'
  'P3v2'
  'F1'
])
param appServicePlanSku string = 'F1'

// Create App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'plan-${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'app'
  properties: {
    reserved: true
  }
}

// Create App Service
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceName
  location: location
  tags: union(tags, {
    'azd-service-name': 'web'  // Add tag required by azd for deployment
  })
  identity: {
    type: 'SystemAssigned' // Add system-assigned managed identity for App Service
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      // Configure Linux container with .NET 8.0
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: false
      // Enable application logging
      httpLoggingEnabled: true
      detailedErrorLoggingEnabled: true
      requestTracingEnabled: true
      logsDirectorySizeLimit: 35
      appSettings: [
        {
          name: 'OpenAIEndpoint'
          value: 'https://jetfinds-openai.openai.azure.com/'
        }
        {
          name: 'OpenAIGptDeployment'
          value: 'gpt-4o'
        }
        {
          name: 'OpenAIEmbeddingDeployment'
          value: 'text-embedding-3-small'
        }
        {
          name: 'SearchServiceUrl'
          value: 'https://regulationsearch.search.windows.net'
        }
        {
          name: 'SearchIndexName'
          value: 'regulations-vector-index'
        }
        {
          name: 'SystemPrompt'
          value: 'You are an AI assistant that helps people find information from their documents. Always cite your sources using the document title.'
        }
        // App Service Logging Configuration
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Development'
        }
        {
          name: 'ASPNETCORE_LOGGING__CONSOLE__DISABLECOLORS'
          value: 'true'
        }
        {
          name: 'ASPNETCORE_LOGGING__LOGLEVEL__DEFAULT'
          value: 'Information'
        }
        {
          name: 'ASPNETCORE_LOGGING__LOGLEVEL__MICROSOFT'
          value: 'Warning'
        }
        {
          name: 'ASPNETCORE_LOGGING__LOGLEVEL__MICROSOFT.ASPNETCORE'
          value: 'Warning'
        }
      ]
    }
  }
}

// ----------------------------------------------------
// Azure OpenAI service
// ----------------------------------------------------

@description('Name of the Azure OpenAI service')
param openAiServiceName string = 'ai-${resourceToken}'

@description('Azure OpenAI service SKU')
param openAiSkuName string = 'S0'

@description('GPT model deployment name')
param openAiGptDeploymentName string = 'gpt-4o'

@description('GPT model name')
param openAiGptModelName string = 'gpt-4o'

@description('GPT model version')
param openAiGptModelVersion string = '2024-11-20'

@description('Embedding model deployment name')
param openAiEmbeddingDeploymentName string = 'text-embedding-3-small'

@description('Embedding model name')
param openAiEmbeddingModelName string = 'text-embedding-3-small'

@description('Embedding model version')
param openAiEmbeddingModelVersion string = '1'


param openAiAccountName string = 'jetfinds-openai'
param openAiResourceGroup string = 'test1'
param openAiSubscriptionId string = '0c1ac98f-cebf-4c89-bfaa-c19ae6bf3dcf'
// Reference the existing OpenAI account

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01' existing = {
  name: openAiAccountName
  scope: resourceGroup(openAiSubscriptionId, openAiResourceGroup)
}
// ----------------------------------------------------
// Role assignments
// ----------------------------------------------------

// ----------------------------------------------------
// Output values
// ----------------------------------------------------



// ----------------------------------------------------
// App Service diagnostics settings
// ----------------------------------------------------

// Create Log Analytics workspace for App Service logs
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Configure diagnostic settings for the App Service
resource appServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: appService
  name: 'appServiceDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
