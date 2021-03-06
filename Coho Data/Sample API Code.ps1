[CmdletBinding()] 
	param(
		[Parameter(Mandatory=$true)]
		[SecureString]$Password,
		[Parameter(Mandatory=$true)]
		[String]$ServerFQDN
  	)
	
	Process {
	
	add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
	[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
	
	### Create authorization string and store in $head
	$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('admin' + ":" + $Password))
	$head = @{"Authorization"="Basic $auth"}
	
	### Authorize the session
	if ($sv.Cookies.Count -eq 0)
		{
		$r1 = Invoke-WebRequest -Uri ("https://" + $ServerFQDN + "/api/auth/login") -Method:Put -Headers $head -ContentType 'application/json' -SessionVariable sv
		}
	
	### Get some data and store into hashtable
	$r2 = (Invoke-WebRequest -Uri ("https://" + $ServerFQDN + "/api/version/") -Method:Get -WebSession $sv).Content | ConvertFrom-Json
	
	### Output data to show it works
	Write-Host "The Datastream is running version $($r2.version)"
	
	}