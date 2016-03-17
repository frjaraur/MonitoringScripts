[CmdletBinding()]
Param(
  [Parameter(Mandatory=$False)]
   [switch]$help,
  [Parameter(Mandatory=$False)]
   [switch]$version,
  [Parameter(Mandatory=$False)]
   [switch]$list
)


$VER="1.1"
# VERSION 1.0 - Initial version
# VERSION 1.1 - Initial release for PaaS broker environment.


#Alias Modulo|| BROKER(true/false) || Parametros (param_1=value1,param_2=value2,param_3=value3...) || TAGS || Umbral_Warning, Umbral_Critico


## ENVIRONMENT - Change to accomplish real environment settings
$TENTACLEOUTDIR="C:\MONITORIZACION\temp"
$COLLECTIONSDIR="C:\MONITORIZACION\collections"



function Usage {
    $me=split-path $MyInvocation.PSCommandPath -Leaf
    echo "VERSION: $VER"
    echo "$me"
    echo "*** Es imprescindible la existencia del fichero de configuracion por defecto C:\MONITORIZACION\collections\PaaS_AD_plugin.cfg "

    exit

}

function GetConfigFile{
    param ([string]$confiddir)
    $scriptname=$(split-path $MyInvocation.PSCommandPath -Leaf ) -replace ".ps1", ""
    $hostname=$($env:COMPUTERNAME)
    $configfilename=$scriptname+"."+$hostname+".cfg"
    $configfile=$(Get-ChildItem -Recurse -Path $confiddir |Where-Object { $_.name -match $configfilename }).FullName
    if (!$configfile){$configfile=$scriptname+".cfg"}
    return $confiddir+"\"+$configfile
}

function PluginError{
    param ([string]$plugin,[string]$severity,[string]$text)
	echo "<module>"
	echo "<name><![CDATA[$plugin]]></name>"
	echo "<type>generic_data_string</type>"
	echo "<description><![CDATA[Plugin Execution Status]]></description>"
	echo "<data><![CDATA[${severity}: $text]]></data>"
    #echo "<tags><![CDATA[$module_tags]]></tags>"
	echo "<str_critical><![CDATA[CRITICAL:]]></str_critical>";
	echo "<str_warning><![CDATA[WARNING:]]></str_warning>";
	echo "</module>"
    exit
}

function Add_Module_xml {
	param ([string]$xmldata,[string]$module_name,[string]$module_type,[string]$module_value,[string]$module_description,[string]$module_tags,[string]$module_thresholds)

	$xmldata= "$xmldata<module>"
    $xmldata="$xmldata\n<name><![CDATA[$module_name]]></name>"
	$xmldata="$xmldata\n<type>$module_type</type>"
	$xmldata="$xmldata\n<description><![CDATA[$module_description]]></description>"


    if($module_thresholds){
        $warn,$crit=$module_thresholds -split ','
        $xmldata="$xmldata\n<str_warning><![CDATA[$warn]]></str_warning>"
        $xmldata="$xmldata\n<str_critical><![CDATA[$crit]]></str_critical>"
    }

    $xmldata="$xmldata\n<data><![CDATA[$module_value]]></data>"
    $xmldata="$xmldata\n<tags><![CDATA[$module_tags]]></tags>"

	$xmldata="$xmldata\n</module>\n"

    return $xmldata

}


function GetCounter{
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

function isServiceRunning{
    param ([string]$name)
    $service=Get-Service -name "$name"
    try
    {
        $service=Get-Service -name "$name"  -ErrorVariable getServiceError -ErrorAction SilentlyContinue
    }
    catch {
        return 0
    }
    if ($service.Status -eq "Running") { return 1 }
    return 0
}

function XMLOut{
    param([string]$xmldata,[string]$xmlfile)
    $xml_lines=$xmldata -split '\\n'

    # Write plugin xml modules data to OUTPUT for Agent
    if (!$xmlfile){
        foreach ($line in $xml_lines){
            if ($line -eq ""){continue}
            echo $line
       }
       return
    }

    # Write plugin xml modules data to file for Broker
    # We need to know date for agent header...
    $now = $(get-date -f "yyyy-MM-dd HH:mm:ss")
    $stream = [System.IO.StreamWriter] $xmlfile
    $stream.WriteLine("<?xml version='1.0' encoding='UTF-8'?>")
    $stream.WriteLine("<agent_data agent_name='$brokername' timestamp='$now' version='5.0' os='$os' os_version='$osversion' interval='300'>")

    foreach ($line in $xml_lines){
        if ($line -eq ""){continue}
            $stream.WriteLine($line)
    }
    $stream.WriteLine("</agent_data>")
    $stream.close()
}




######## Main

$plugin_name="PaaS_AD_plugin_"+$VER

if ($help -or $version){ Usage }


#DISP_Servicio_Netlogon
#DISP_Servicio_Intersite_Messaging
#DISP_Servicio_DNS
#DISP_Servicio_Kerberos_Key_Distribution_Center
#DISP_Servicio_Active_directory_domain_services
#AD_LDAP Client Sessions
#AD_DRA SyncRequestsMade



#Define all modules that could be created by this plugin
$modules_in_plugin = @{
     "Servicio" = @{
        module_type = "generic_proc";
        module_name = "DISP_Servicio %nombre_servicio%";
        module_description = "Servicio %nombre_servicio%";
        }
     "Contador_AD_LDAP Client Sessions" = @{
        module_type = "generic_proc";
        module_name = "AD_LDAP Client Sessions";
        module_description = "AD_LDAP Client Sessions";
		module_counter= "\NTDS\LDAP Client Sessions";
        }
     "Contador_AD_DRA SyncRequestsMade" = @{
        module_type = "generic_proc";
        module_name = "AD_DRA SyncRequestsMade";
        module_description = "AD_DRA SyncRequestsMade";
		module_counter= " \NTDS\DRA Sync Requests Made";
        }
}


# List All available modules that this plugin could check
if ($list){
    $arr_modules_in_plugin = $modules_in_plugin.Keys
    foreach ($a in $arr_modules_in_plugin){
        echo "`n$a"
        foreach ($k in ($modules_in_plugin[$a]).Keys){
            echo "`t$k`t->`t'$($modules_in_plugin[$a][$k])'"
        }
    }
    exit
}





# DefaultConfigfile if specific Configfile does not exist
$plugin_configfile=GetConfigFile($COLLECTIONSDIR)
if (-not (Test-Path $plugin_configfile)){
    PluginError $plugin_name "CRITICAL" "ERROR: No se encontro el fichero $plugin_configfile"
}

# Tentacle Agent Output Dir
$xml_out_dir=$TENTACLEOUTDIR

# Configuration for modules from configfile
$cfg_modules=@{}

# Agent
$xml_agent=""
$agent_data=@{}

# Broker
$brokersuffix="SALUD"
$xml_broker=""
$broker_data=@{}

# For each line in configuration file do its check and add data to its own module
foreach ($cfgline in [System.IO.File]::ReadLines($plugin_configfile)) {

    #Avoid Comments and Empty Lines
    if($cfgline -match "((^#)|(^\s+$))" ){continue}
	
    # Initiate as Agent only
    $isbroker=$false

    # Configuration Fields comma delimited by '||' (two pipes)
    $alias, $isbroker, $parameters, $tags, $thresholds=$cfgline -split '\|\|'

    # Avoid left and rigth spaces in alias (spaces at both sides are allowed for better reading)
    $alias=$alias.trim()

    # Create an empty table/hash for this check from file
    $cfg_modules[$alias]=@{}

    # Give name for this "configuration line"
    $cfg_modules[$alias]["alias"]=$alias


    # Check if exists isbroker field
    if (!$isbroker){
        $isbroker=$false
    }else{
        $isbroker=$isbroker.trim()
        if ($isbroker -eq "" -or $isbroker.ToUpper() -ne "TRUE"){$isbroker=$false}
    }

    # Thresholds
    if(!$thresholds){$thresholds=""}



    # Take parameters from configuration and sepaparate them into param=value with ',' as delimiter
    if ($parameters){
        $parameters=$parameters.trim();
        $parameters=$parameters -split ','
        $cfg_modules[$alias]["parameters"]=$parameters
        if ($parameters -notlike "^ "){
            $cfg_modules[$alias]["parameters"]=@{}
            foreach ($paramline in $parameters){
                $pname,$pvalue=$paramline -split '='

                # Create hash table with parameters
                $cfg_modules[$alias]["parameters"][$pname]=$pvalue
            }
        }
    }
    if ($tags){$cfg_modules[$alias]["tags"]=$tags.trim()}
    if ($thresholds){$cfg_modules[$alias]["thresholds"]=$thresholds.trim()}

    #$parameters=$cfg_modules[$alias]["parameters"] -split ','


    ## Monitoring
    #
    # Every configured check in file is done just one time and value is added for agent and for broker too, this way both have same value even it is needed or not
    #

    #Service Monitoring
    if ($alias -match "(^Servicio$)" ){
        $servicename= $cfg_modules[$alias]["parameters"]["servicio"]
        $module_name=$modules_in_plugin["Servicio"]["module_name"] -replace "%nombre_servicio%", "$servicename"
        $module_type=$modules_in_plugin["Servicio"]["module_type"]
        $module_description=$modules_in_plugin["Servicio"]["module_description"] -replace "%nombre_servicio%", "$servicename"


        if(!$agent_data[$module_name]){
            $module_value=isServiceRunning "$servicename"
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }

        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"] $thresholds
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"] $thresholds

        }

    }

	# We could just use "Contador" as alias string and counter could be a parameter... but someone can write down anything in configuration...
	# and we choose to use specific fixed counter names ....
    if ($alias -match "(^Contador_AD_LDAP Client Sessions$)" ){

        $instance= $cfg_modules[$alias]["parameters"]["instancia"]
        $module_name=$modules_in_plugin["Contador_AD_LDAP Client Sessions"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["Contador_AD_LDAP Client Sessions"]["module_type"]
        $module_description=$modules_in_plugin["Contador_AD_LDAP Client Sessions"]["module_description"] -replace "%instancia%", "$instance"
        $counter=$modules_in_plugin["Contador_AD_LDAP Client Sessions"]["module_counter"]

        if(!$agent_data[$module_name]){
            $module_value=GetCounter "$counter"
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }

        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"] $thresholds
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"] $thresholds
        }
    }
	
    if ($alias -match "(^Contador_AD_DRA SyncRequestsMade$)" ){

        $instance= $cfg_modules[$alias]["parameters"]["instancia"]
        $module_name=$modules_in_plugin["Contador_AD_DRA SyncRequestsMade"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["Contador_AD_DRA SyncRequestsMade"]["module_type"]
        $module_description=$modules_in_plugin["Contador_AD_DRA SyncRequestsMade"]["module_description"] -replace "%instancia%", "$instance"
        $counter=$modules_in_plugin["Contador_AD_DRA SyncRequestsMade"]["module_counter"]

        if(!$agent_data[$module_name]){
            $module_value=GetCounter "$counter"
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }

        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"] $thresholds
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"] $thresholds
        }
    }	
}


# Checks from configuration file are done... so print their results

# For Agent just print OUT xml module tags
XMLOut ("$xml_agent")

# If there is any data for broken agent create a file with all its xml module tags and agent headers/end
if ($xml_broker -ne ""){

    # Theses data is needed jut in case of broker agent
    $brokername=$($env:COMPUTERNAME) + "_" + $brokersuffix
    $os="Windows"
    $osversion=(Get-WmiObject Win32_OperatingSystem).Caption

    # Filename will be created using a random float number between 0 and 1000 (we replace decimal symbol if needed...) and brokername
    $randomseed=$(Get-Random -Minimum 0.0 -Maximum 1000) -replace ",", "."
    $xml_outfile_broker=$xml_out_dir+"\"+$brokername+$randomseed+".data"

    # For broken agent print xml modules in file for tentacle
    XMLOut "$xml_broker" "$xml_outfile_broker"
}
