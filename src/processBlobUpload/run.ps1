using namespace System.Net

# Input bindings are passed in via param block.
param($InputBlob, $TriggerMetadata)

# Define functions first
function Get-StorageContext {
    try {
        # Get storage account context using environment variables
        $storageAccountName = $env:PDFProcessorSTORAGE__accountName
        $connectionString = $env:PDFProcessorSTORAGE
        
        # Check if running locally with Azurite
        if ($connectionString -eq "UseDevelopmentStorage=true") {
            # For local development with Azurite
            Write-Host "Using Azurite for local development"
            return New-AzStorageContext -ConnectionString $connectionString
        } elseif ($storageAccountName) {
            # For Azure with managed identity - use OAuth authentication
            # Authentication is handled in profile.ps1 for better performance and to avoid race conditions
            Write-Host "Using managed identity for storage access with account: $storageAccountName"
            
            # Create storage context using OAuth (managed identity already authenticated in profile.ps1)
            $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
            return $ctx
        } else {
            throw "No valid storage configuration found. Check PDFProcessorSTORAGE settings."
        }
    } catch {
        Write-Error "Failed to create storage context: $_"
        throw
    }
}

function Copy-ToProcessedContainer {
    param(
        [byte[]]$BlobData,
        [string]$BlobName
    )
    
    Write-Host "Starting copy operation for $BlobName"
    
    try {
        $context = Get-StorageContext
        
        # Convert byte array to temporary file for upload
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllBytes($tempFile, $BlobData)
            
            # Upload blob to processed-pdf container using streams
            $result = Set-AzStorageBlobContent -Context $context `
                -Container "processed-pdf" `
                -Blob $BlobName `
                -File $tempFile `
                -BlobType Block `
                -Force
            
            Write-Host "Successfully copied $BlobName to processed-pdf container"
            return $result
        }
        finally {
            # Clean up temporary file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
    } catch {
        Write-Error "Failed to copy $BlobName to processed container: $_"
        throw
    }
}

# Get blob properties
$blobName = $TriggerMetadata.Name
$fileSize = $InputBlob.Length

# Write information log with current time and blob details
Write-Host "PowerShell Blob Trigger (using Event Grid) processed blob"
Write-Host "Name: $blobName"
Write-Host "Size: $fileSize bytes"

# Copy the blob to the processed container with a new name
$newBlobName = "processed-$blobName"

try {
    # Check if blob already exists in processed container to avoid duplicate processing
    $context = Get-StorageContext
    $existingBlob = Get-AzStorageBlob -Context $context -Container "processed-pdf" -Blob $newBlobName -ErrorAction SilentlyContinue
    
    if ($existingBlob) {
        Write-Host "Blob $newBlobName already exists in the processed container. Skipping upload."
        return
    }

    # Here you can add any processing logic for the input blob before uploading it to the processed container.
    
    # Copy blob to processed container using streams
    Copy-ToProcessedContainer -BlobData $InputBlob -BlobName $newBlobName
    
    Write-Host "PDF processing complete for $blobName. Blob copied to processed container with new name $newBlobName."
} catch {
    Write-Error "Error processing blob $blobName : $_"
    throw
}