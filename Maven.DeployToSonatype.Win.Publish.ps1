<#
.SYNOPSIS
Sonatype Central 包发布及状态轮询脚本
.DESCRIPTION
实现包发布、发布状态查询，并持续轮询直到发布完成
#>

# ====================== 配置项（请根据实际情况修改） ======================
$sonatypeUsername = "GEL7cU"                                 # 用户名
$sonatypeApiToken = "3PlnBdLszRsqGvcgzB8w2XXhJopybJeoU"      # API Token
$packageFilePath = "C:\path\to\your\package.zip"             # 待发布包的本地路径
$pollingIntervalSeconds = 60                                 # 状态查询间隔（秒）
$maxPollingTimes = 100                                       # 最大轮询次数（防止无限循环）
# ==========================================================================


# 1. 构建Basic Auth认证头
$authString = $sonatypeUsername + ":" + $sonatypeApiToken
$authBytes = [System.Text.Encoding]::UTF8.GetBytes($authString)
$authBase64 = [System.Convert]::ToBase64String($authBytes)
$headers = @{
    "accept"        = "*/*"
    "Authorization" = "Basic $authBase64"
    "Content-Type"  = "application/json"
}
$validatedPath = "";

# 2. 查询最新的DeploymentId
function Get-DeploymentId {
    param()

    try {
        $ApiUrl = "https://central.sonatype.com/api/v1/publisher/deployments/files"
        $requestBody = @{
            page            = 0
            size            = 1
            sortField       = "createTimestamp"
            sortDirection   = "desc"
            pathStarting    = "org/sonatype/nexus/"
        }
        
        # 将哈希表序列化为JSON字符串（确保格式正确，无多余转义）
        $requestBodyJson = $requestBody | ConvertTo-Json -Compress

        # 发送POST请求
        $response = Invoke-RestMethod -Uri $ApiUrl `
            -Method Post `
            -Headers $headers `
            -Body $requestBodyJson `
            -ErrorAction Stop
            
        if (-not $response) {
            exit 1
        }
        if ($response.deployments[0].deploymentState -eq "VALIDATED") {
            $script:validatedPath = $response.deployments[0].deployedComponentVersions[0].path
        }
        
        return $response.deployments[0].deploymentId
    }
    catch {
        Write-Warning "$($_.Exception.Message)"
        return $null
    }
}

# 3. 查询发布状态
function Get-ReleaseStatus {
    param(
        [string]$DeploymentId
    )

    try {
        $statusUrl = "https://central.sonatype.com/api/v1/publisher/status?id=$DeploymentId"
        $response = Invoke-RestMethod -Uri $statusUrl -Method Post -Headers $headers
        
        # 返回状态（需根据接口返回格式调整，示例状态：PENDING/IN_PROGRESS/PUBLISHED/FAILED/VALIDATED）
        return $response.deploymentState
    }
    catch {
        Write-Warning "$($_.Exception.Message)"
        return $null
    }
}

# 4. 上传成功后的发布
function PublishComponent {
    param(
        [string]$DeploymentId
    )

    try {
        $statusUrl = "https://central.sonatype.com/api/v1/publisher/deployment/$DeploymentId"
        $response = Invoke-RestMethod -Uri $statusUrl -Method Post -Headers $headers
        return "200"
    }
    catch {
        Write-Warning "$($_.Exception.Message)"
        return $null
    }
}

# 5. 轮询发布状态直到完成
function Wait-ReleaseCompletion {
    param(
        [string]$DeploymentId,
        [int]$IntervalSeconds,
        [int]$MaxTimes
    )

    $currentTimes = 0
    while ($currentTimes -lt $MaxTimes) {
        $currentTimes++
        $status = Get-ReleaseStatus -DeploymentId $DeploymentId

        if (-not $status) {
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]: $status"

        # 状态判断（需根据Sonatype实际状态值调整）
        switch ($status) {
            "PUBLISHED" {
                Write-Host "`nFinish deploymentId: $DeploymentId"
                return $true
            }
            "FAILED" {
                Write-Error "`nFailed deploymentId: $DeploymentId"
                exit 1
            }
            default {
                # 未完成，继续轮询
                Start-Sleep -Seconds $IntervalSeconds
            }
        }
    }

    Write-Error "`nTimeout $MaxTimes"
    exit 1
}



$deploymentId  = Get-DeploymentId
$releaseStatus = Get-ReleaseStatus -DeploymentId $deploymentId
Write-Host "deploymentId : $deploymentId , Status: $releaseStatus" 
if (-not $releaseStatus) {
    exit 1
}
switch ($releaseStatus) {
    "PUBLISHED" {
        Write-Host "`nFinish nPublish：$DeploymentId"
        exit 0
    }
    "VALIDATED" {
        Write-Host "Publishing: $validatedPath"
        $publishRet = PublishComponent -DeploymentId $deploymentId
        if (-not $publishRet) {
            exit 1
        }
        Write-Host "Publish Succeed: $publishRet"
    }
    default {
        # 未完成，继续轮询
        Start-Sleep -Seconds $pollingIntervalSeconds
    }
}

# 轮询等待发布完成
Wait-ReleaseCompletion -DeploymentId $deploymentId -IntervalSeconds $pollingIntervalSeconds -MaxTimes $maxPollingTimes
