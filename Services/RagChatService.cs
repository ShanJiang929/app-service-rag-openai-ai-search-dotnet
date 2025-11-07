using Azure;
using Azure.AI.OpenAI;
using System.ClientModel;
using Azure.AI.OpenAI.Chat;
using OpenAI.Chat;
using Azure.Identity;
using BlazorAISearch.Models;

namespace BlazorAISearch.Services;

#pragma warning disable AOAI001

/// <summary>
/// Service that provides Retrieval Augmented Generation (RAG) capabilities
/// by connecting Azure OpenAI with Azure AI Search for grounded responses.
/// </summary>
public class RagChatService
{
    private readonly AppSettings _settings;
    private readonly ILogger<RagChatService> _logger;
    private readonly AzureOpenAIClient _openAIClient;
    private readonly ChatClient _chatClient;

    public RagChatService(AppSettings settings, ILogger<RagChatService> logger)
    {
        _settings = settings;
        _logger = logger;

        // Validate required settings for Azure OpenAI and Azure AI Search
        ArgumentNullException.ThrowIfNull(_settings.OpenAIEndpoint);
        ArgumentNullException.ThrowIfNull(_settings.OpenAIGptDeployment);
        ArgumentNullException.ThrowIfNull(_settings.SearchServiceUrl);
        ArgumentNullException.ThrowIfNull(_settings.SearchIndexName);
        
        // Initialize Azure OpenAI client for chat completions with system-assigned managed identity
        _openAIClient = new AzureOpenAIClient(
            new Uri(_settings.OpenAIEndpoint),
            new DefaultAzureCredential()
        );
        _chatClient = _openAIClient.GetChatClient(_settings.OpenAIGptDeployment);

        _logger.LogInformation("RagChatService initialized with settings");
    }

    /// <summary>
    /// Processes a chat completion request with RAG capabilities by integrating with Azure AI Search.
    /// </summary>
    /// <param name="history">The chat history containing previous messages</param>
    /// <returns>A response containing the AI-generated content and any relevant citations</returns>
    public async Task<ChatResponse> GetChatCompletionAsync(List<ChatMessage> history)
    {
        try
        {
            // Limit chat history to the 10 most recent messages to prevent token limit issues
            var recentHistory = history.Count <= 20
                ? history
                : history.Skip(history.Count - 20).ToList();

            // Add system message to provide context and instructions to the model
            var messages = recentHistory.Prepend(new SystemChatMessage(_settings.SystemPrompt ?? throw new ArgumentNullException(nameof(_settings.SystemPrompt))));
            // Configure the chat completion with Azure AI Search as a data source
            ChatCompletionOptions options = new();

            options.AddDataSource(new AzureSearchChatDataSource()
            {
                Endpoint = new Uri(_settings.SearchServiceUrl ?? throw new ArgumentNullException(nameof(_settings.SearchServiceUrl))),
                IndexName = _settings.SearchIndexName,
                Authentication = DataSourceAuthentication.FromSystemManagedIdentity(), // Use system-assigned managed identity
                QueryType = DataSourceQueryType.Vector, // Combines vector search with keyword matching and semantic ranking
                VectorizationSource = DataSourceVectorizer.FromDeploymentName(_settings.OpenAIEmbeddingDeployment),
                FieldMappings = new DataSourceFieldMappings
                {
                    ContentFieldNames = { "content" },      // using collection initializer
                    VectorFieldNames  = { "contentVector" } // using collection initializer
                }
            });

            var result = await _chatClient.CompleteChatAsync(messages, options);

            var ctx = result.Value.GetMessageContext();

            var response = new ChatResponse
            {
                Content = result.Value.Content,
                Citations = ctx?.Citations
            };

            return response;
        }
        // catch (Exception ex)
        // {
        //     _logger.LogError(ex, "Error in GetChatCompletionAsync");
        //     return new ChatResponse 
        //     { 
        //         Error = $"An error occurred: {ex.Message}" 
        //     };
        catch (Azure.RequestFailedException rfe)
        {
           _logger.LogError(rfe, "Azure RequestFailedException: Status={Status}, ErrorCode={ErrorCode}, Message={Message}",
               rfe.Status, rfe.ErrorCode, rfe.Message);
         _logger.LogDebug("Full exception: {Ex}", rfe.ToString());
          return new ChatResponse { Error = $"Azure RequestFailedException: {rfe.Status} {rfe.ErrorCode} {rfe.Message}" };
     }
       catch (System.ClientModel.ClientResultException cre)
       {
           _logger.LogError(cre, "ClientResultException: {Message}", cre.Message);
          _logger.LogDebug("Full exception: {Ex}", cre.ToString());
          return new ChatResponse { Error = $"ClientResultException: {cre.Message}" };
      }
     catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error in GetChatCompletionAsync: {Message}", ex.Message);
            return new ChatResponse { Error = $"An error occurred: {ex}" };
        }
        
    }
}