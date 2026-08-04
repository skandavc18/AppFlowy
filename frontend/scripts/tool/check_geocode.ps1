# Checks whether OpenStreetMap can resolve an address the map failed to place.
param([string]$Address = "BnM, 205, Mile End Road, Stepney, London Borough of Tower Hamlets, Greater London, England, E1 4AA, United Kingdom")

$query = [uri]::EscapeDataString($Address)
$uri = "https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1"
try {
  $response = Invoke-WebRequest -Uri $uri -Headers @{ 'User-Agent' = 'AppFlowy/0.11.4' } -TimeoutSec 25
  Write-Output "STATUS $($response.StatusCode)"
  Write-Output $response.Content.Substring(0, [Math]::Min(400, $response.Content.Length))
} catch {
  Write-Output "FAILED: $($_.Exception.Message)"
}
