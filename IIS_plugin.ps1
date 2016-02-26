[CmdletBinding()]
Param(
#  [Parameter(Mandatory=$False)]
#   [string]$instances,
  [Parameter(Mandatory=$False)]
   [string]$tags,
  [Parameter(Mandatory=$False)]
   [switch]$help,
  [Parameter(Mandatory=$False)]
   [switch]$version
)


$VER="1.0"
# VERSION 1.0 - Initial version

#Internet Information Server:
#-          IIS: Estado de Instancias
#-          IIS: Servicio W3SVC
#-          IIS: Servicio IISADMIN


function Usage {
    $me=split-path $MyInvocation.PSCommandPath -Leaf
    echo "VERSION: $VER"
    echo "$me [-tags  $([char]34)TAG1,TAG2$([char]34)] [-help] [-version]"
    exit
}

function PluginError{
    param ([string]$plugin,[string]$severity,[string]$text)
	echo "<module>"
	echo "<name><![CDATA[$plugin]]></name>"
	echo "<type>generic_data_string</type>"
	echo "<description><![CDATA[Plugin Execution Status]]></description>"
	echo "<data><![CDATA[${severity}: $text]]></data>"
    #echo "<tags><![CDATA[$module_tags]]></tags>"
	echo "<str_critical><![CDATA[CRITICAL:]]></str_critical>\n";
	echo "<str_warning><![CDATA[WARNING:]]></str_warning>\n";
	echo "</module>"
    exit
}


function Module_xml {
	param ([string]$module_name,[string]$module_type,[string]$module_value,[string]$module_description,[string]$module_tags)

	echo "<module>"
	echo "<name><![CDATA[$module_name]]></name>"
	echo "<type>$module_type</type>"
	echo "<description><![CDATA[$module_description]]></description>"
	echo "<data><![CDATA[$module_value]]></data>"
    echo "<tags><![CDATA[$module_tags]]></tags>"
	echo "</module>"

}


function GetServiceStatusByName{
    param ([string]$srvname)
    #Get-Service | where-object { $_.DisplayName -match "SQL Server \($instance\)" } | foreach-object {echo $_.Status;if ($_.Status -eq "Running") { return 1 }}
    try
    {
        $service=Get-Service -name "$srvname"  -ErrorVariable getServiceError -ErrorAction SilentlyContinue
    }
    catch {
        return 0
    }
    if ($service.Status -eq "Running") { return 1 }
    return 0
}

function GetCounterValue{
    param ([string]$counter)
    try{
            $metricdata=(Get-Counter $counter -ErrorVariable getServiceError -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        }
    catch{
            $metricdata=0
        }
    return $metricdata
}


function CleanArraySpaces{
    param([array]$array)
    $cleanarray = @()
    foreach ($I in $array) {
        $I=$I.Trim()
        #write-host "TRIMMED - [$I]"
        $cleanarray += $I
    }
    return $cleanarray
}


if ($help -or $version){ Usage }

$hostname=$env:computername
$PluginName="Plugin IIS PaaS"
$modules_prefix="IIS "

# We are using Display Name for Best Module Information
$services=("W3SVC","IISADMIN")

foreach ($service in $services) {

        # Get Service Status
        $module_name=$modules_prefix+"Service Status $service"
        $module_type="generic_proc"
        $module_description="AD Service Status for ${service}."
        $module_value=GetServiceStatusByName "$service"
        
        Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
}


# We left counter checks commented for future usage
#$counters = @{
#    "LDAP Client Sessions"="\NTDS\LDAP Client Sessions"
#    "DRA Outbound Bytes total/sec" = "\NTDS\DRA Outbound Bytes Total/sec"
#    "DRA Sync Requests Made" = "\NTDS\DRA Sync Requests Made" 
#}

#$counter_names=$counters.Keys

#foreach ($counter_name in $counter_names) {
#    $module_name=$modules_prefix +$counter_name
#    $module_type="generic_data"
#    $module_description=$counter_name
#    $module_value=GetCounterValue $counters.$counter_name

#    Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
#}


Import-Module WebAdministration


### Site Status


try {
        $sites=(dir IIS:\Sites -ErrorVariable getServiceError -ErrorAction SilentlyContinue|select-object -property Name,State)
    }
catch {
        $sites=@()
    }

foreach ($site in $sites) {
    $module_name=$modules_prefix+"Site Status '"+$site.Name+"'"
    $module_type="generic_proc"
    $module_description="Site Status '"+$site.Name+"'"
    $status=0
    if ($site.State -like "Started" ){$status=1}
    $module_value=$status
        
    Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

}


### Application Pools
try {
        $apppools=(dir IIS:\AppPools -ErrorVariable getServiceError -ErrorAction SilentlyContinue|select-object -property Name,State,PSPath)
    }
catch {
        $apppools=@()
    }

foreach ($app in $apppools) {
    $app_name=$app.Name
    $module_name=$modules_prefix+"APP Pool Status '"+$app.Name+"'"
    $module_type="generic_proc"
    $module_description="APP Pool Status '"+$app.Name+"' ("+$app.PSPath+")"
    $status=0
    if ($app.State -like "Started" ){$status=1}
    $module_value=$status
        
    Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

}
