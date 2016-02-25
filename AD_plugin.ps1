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

#module_plugin powershell c:\MONITORIZACION\collections\ConvergentesSist\Pruebas\PaaS_AD_plugin.ps1 -tags 'TEST1,TEST2'
# VERSION 1.0 - Initial version

#         Active Directory: Servicio Netlogon
#         Active Directory: Servicio  Intersite Messaging
#         Active Directory: Servicio Cliente DNS
#         Active Directory: Servicio Kerberos Key Distribution Center
#         Active Directory: N. de sesiones de cliente LDAP conectados
#         Active Directory: Bytes/sg enviados
#         Active Directory: N. de sesiones de cliente LDAP conectados
#         Active Directory: N. de solicitudes de sincronizacion.


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


function GetServiceStatus{
    param ([string]$srvdispname)
    #Get-Service | where-object { $_.DisplayName -match "SQL Server \($instance\)" } | foreach-object {echo $_.Status;if ($_.Status -eq "Running") { return 1 }}
    try
    {
        $service=Get-Service -displayname "$srvdispname"  -ErrorVariable getServiceError -ErrorAction SilentlyContinue
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
$PluginName="Plugin AD PaaS"
$modules_prefix="AD "

# Define what services must been checked. We are using Display Name for Best Module Information
$services=("Netlogon","Kerberos Key Distribution Center","Intersite Messaging","DNS Client")

foreach ($service in $services) {

        # Get Service Status
        $module_name=$modules_prefix+"Service Status $service"
        $module_type="generic_proc"
        $module_description="AD Service Status for ${service}."
        $module_value=GetServiceStatus "$service"
        
        Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
}

# Defiene Counters to check on a hash table, using a 'Display Name' and the Real Counter Path.
$counters = @{
    "LDAP Client Sessions"="\NTDS\LDAP Client Sessions"
    "DRA Outbound Bytes total/sec" = "\NTDS\DRA Outbound Bytes Total/sec"
    "DRA Sync Requests Made" = "\NTDS\DRA Sync Requests Made" 
}

$counter_names=$counters.Keys

foreach ($counter_name in $counter_names) {
    $module_name=$modules_prefix +$counter_name
    $module_type="generic_data"
    $module_description=$counter_name
    $module_value=GetCounterValue $counters.$counter_name

    Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

}
