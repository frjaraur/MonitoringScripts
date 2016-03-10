[CmdletBinding()]
Param(
  [Parameter(Mandatory=$False)]
   [string]$instances,
  [Parameter(Mandatory=$False)]
   [string]$tags,
  [Parameter(Mandatory=$False)]
   [switch]$help,
  [Parameter(Mandatory=$False)]
   [switch]$version,
  [Parameter(Mandatory=$False)]
   [switch]$list
)


$VER="1.2"
# VERSION 1.0 - Initial version
# VERSION 1.1 - Avoid Common Counters if Cluster Resources not Running on Node
# VERSION 1.2 - Initial release for PaaS broker environment.


#Alias Modulo|| BROKER(true/false) || Parametros (param_1=value1,param_2=value2,param_3=value3...) || TAGS || Umbral_Warning, Umbral_Critico
#Servicio||     ||servicio=MSSQLSERVER || TAG1, TAG2 ||
#Servicio|| ||servicio=SQLSERVERAGENT || TAG1, TAG2 ||
#MSSQL_Conectividad || || instancia=MSSQLSERVER || TAG1,TAG2
#MSSQLQuery_UsuariosConectados || || instancia=MSSQLSERVER || TAG1,TAG2
#MSSQLQuery_ConexionesIniciadas || || instancia=MSSQLSERVER || TAG1,TAG2
#MSSQL_TamanoArchivosDatos || || instancia=MSSQLSERVER || TAG1,TAG2
#Contador_LatenciaBloqueos || ||  || TAG1,TAG2
#Servicio||true||servicio=SQLSERVERAGENT || TAG1, TAG2 ||




function Usage {
    $me=split-path $MyInvocation.PSCommandPath -Leaf
    echo "VERSION: $VER"
    echo "*** Es imprescindible especificar al menos las instancias a monitorizar separadas por ',' "

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


function SQLQueryMetric{
    param ([string]$instance,[string]$query)
    Try
      {
            $result=(Invoke-Sqlcmd -ServerInstance $instance -Query $query  -ErrorVariable getServiceError -ErrorAction SilentlyContinue).Column1 
       }
    Catch
        {
            $result=0
        }

    return $result
}


function SQLConnectivity{
    param ([string]$instance)
    Try
      {
            $result=(Invoke-Sqlcmd -ServerInstance $instance -Query "@@VERSION"  -ErrorVariable getServiceError -ErrorAction SilentlyContinue).Column1
            $result=1 # We don't care about version 
       }
    Catch
        {
            $result=0
        }

    return $result
}



function SQLDBSizes{
    param ([string]$instance)
    $hdbsizes = @{}
    $results=(Invoke-Sqlcmd -ServerInstance $instance -Query "exec sp_helpdb" -ErrorVariable getServiceError -ErrorAction SilentlyContinue)
	foreach ($result in $results) {
        $dbname=$result.Name
        $d=$result.db_size.trim()
        [int]$dbsize,$meassure=$d -split ' '
        if ($meassure -like "MB"){$m=1024}
        if ($meassure -like "GB"){$m=1024*1024}
        $dbsize=$dbsize*$m
        echo "$dbname [$d] $dbsize KB "
        $hdbsizes.Add($dbname, $dbsize)
	}

    return $hdbsizes
}

function SQLServiceInstanceRunning{
    param ([string]$instance)
    
    #Clean netbios hostname or resourcegroup name (Avoid '\' from SQL Server Instance Name or it will not work :| )
    $dummy,$ins=$instance -split '\\';if ($ins -like ""){$ins=$instance}


    #Get-Service | where-object { $_.DisplayName -match "SQL Server \($instance\)" } | foreach-object {echo $_.Status;if ($_.Status -eq "Running") { return 1 }}
    try
    {
        $service=Get-Service -displayname "SQL Server ($ins)"  -ErrorVariable getServiceError -ErrorAction SilentlyContinue
    }
    catch {
        return 0
    }
    if ($service.Status -eq "Running") { return 1 }
    return 0
}

function SQLServiceAgentRunning{
    param ([string]$instance)
    
    #Clean netbios hostname or resourcegroup name (Avoid '\' from SQL Server Instance Name or it will not work :| )
    $dummy,$ins=$instance -split '\\';if ($ins -like ""){$ins=$instance}


    #Get-Service | where-object { $_.DisplayName -match "SQL Server \($instance\)" } | foreach-object {echo $_.Status;if ($_.Status -eq "Running") { return 1 }}
    try
    {
        $service=Get-Service -displayname "SQL Server Agent ($ins)"  -ErrorVariable getServiceError -ErrorAction SilentlyContinue
    }
    catch {
        return 0
    }
    if ($service.Status -eq "Running") { return 1 }
    return 0
}


function SQLGetCounter{
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

function SQLClusterResourceUp{
        # Obtain Cluster Resource Names instead of Hostnames for a Cluster Environment
        Try{
            Get-ClusterNode $hostname   -ErrorVariable getServiceError -ErrorAction SilentlyContinue| Get-ClusterResource | where-object {$_.ResourceType.name -eq "SQL Server Availability Group"}|foreach-object {
                $sqlclusterresources+= $_.Name
            }
        }
        Catch{
            $sqlclusterresources+= $hostname
        }
        return $sqlclusterresources
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


function SimpleServiceModule{
    param([string]$servicename,[hashtable]$plugin,[hastable]$config)   
        $module_name=$modules_in_plugin["Servicio_%nombre_servicio%"]["module_name"] -replace "%nombre_servicio%", "$servicename"
        $module_type=$modules_in_plugin["Servicio_%nombre_servicio%"]["module_type"]
        $module_description=$modules_in_plugin["Servicio_%nombre_servicio%"]["module_description"] -replace "%nombre_servicio%", "$servicename"
        $module_value=isServiceRunning "$servicename"
        return $module_name,$module_type,$module_description,$module_value
}


function MSSQLInstance{
    param([string]$instance)
    # This is not "True" in cluster service environments... we should use SQLClusterResourceUp $env:computername
    if ($instance -like "MSSQLSERVER" -or $instance -like "*\MSSQLSERVER"){$instance=($env:computername)}
    return $instance
}

######## Main


#SQLServer
#          MSSQL Server: Conectividad con una instancia
#          MSSQL Server: Servicio MSSQL$INSTANCIA
#          MSSQL Server: Servicio SQLAgent$INSTANCIA
#          MSSQL Server: N. de Usuarios conectados
#          MSSQL Server: Tamano (en kilobytes) de todos los archivos de datos
#          MSSQL Server: Latencia  para bloqueos
#          MSSQL Server: N.  total de conexiones iniciadas


#Define all modules that could be created by this plugin
$modules_in_plugin = @{
     "Servicio" = @{ 
        module_type = "generic_proc"; 
        module_name = "Servicio %nombre_servicio%"; 
        module_description = "Servicio %nombre_servicio%";
        } 
     "MSSQL_Conectividad" = @{ 
        module_type = "generic_proc"; 
        module_name = "Conectividad con instancia %instancia%"; 
        module_description = "Conectividad con instancia %instancia%";
        } 
     "MSSQLQuery_UsuariosConectados" = @{ 
        module_type = "generic_proc"; 
        module_name = "N. de usuario conectados %instancia%"; 
        module_description = "N. de usuario conectados %instancia%";
        module_query = "select @@connections";
        }
     "MSSQL_TamanoArchivosDatos" = @{ 
        module_type = "generic_proc"; 
        module_name = "Tamano (en kilobytes) archivos de datos %instancia%"; 
        module_description = "Tamano (en kilobytes) de todos los archivos de datos %instancia%";
        }
     "Contador_LatenciaBloqueos" = @{ 
        module_type = "generic_proc"; 
        module_name = "Latencia Bloqueos"; 
        module_description = "Latencia Bloqueos";
        module_counter= "\SQLServer:Locks(_total)\Lock Waits/sec";
        }
     "MSSQLQuery_ConexionesIniciadas" = @{ 
        module_type = "generic_proc"; 
        module_name = "N.  total de conexiones iniciadas %instancia%"; 
        module_description = "N.  total de conexiones iniciadas %instancia%";
        module_query ="SELECT COUNT(dbid) as Column1 FROM sys.sysprocesses WHERE dbid > 0";
        }
}



# Default Configfile if specific Configfile does not exist
$plugin_default_configfile="C:\MONITORIZACION\PaaS_SQLServer_plugin.cfg"

$plugin_configfile="C:\MONITORIZACION\PaaS_SQLServer_plugin.yomismo.cfg"

if (-not (Test-Path $plugin_configfile)){$plugin_configfile=$plugin_default_configfile}

# Tentacle Agent Output Dir

$xml_out_dir="C:\MONITORIZACION\temp"






if ($help -or $version){ Usage }

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


# Configuration for modules from configfile
$cfg_modules=@{}

#Agent
$xml_agent=""
$agent_data=@{}

#Broker
$brokersuffix="SALUD"
$xml_broker=""
$broker_data=@{}


foreach ($cfgline in [System.IO.File]::ReadLines($plugin_configfile)) {
    #Avoid Comments
    if($cfgline -match "((^#)|(^\s+$))" ){continue}

    $isbroker=$false

    #$alias, $isbroker, $parameters, $tags, $thresholds=@()

    #Alias Modulo || BROKER(true/false) || Parametros (param_1=value1,param_2=value2,param_3=value3...) || TAGS || Umbral Warning, Umbral Critico ||
    $alias, $isbroker, $parameters, $tags, $thresholds=$cfgline -split '\|\|'
   
    $alias=$alias.trim()

    $cfg_modules[$alias]=@{}

    $cfg_modules[$alias]["alias"]=$alias
 
    
    # Check if something is in isbroker column
    if (!$isbroker){
        $isbroker=$false
    }else{
        $isbroker=$isbroker.trim()
        if ($isbroker -eq "" -or $isbroker.ToUpper() -ne "TRUE"){$isbroker=$false}
    }

    if ($parameters){
        $parameters=$parameters.trim();
        $cfg_modules[$alias]["parameters"]=$parameters
        if ($parameters -notlike "^ "){
            $cfg_modules[$alias]["parameters"]=@{}
            foreach ($paramline in $parameters){
                $pname,$pvalue=$paramline -split '='
                #echo "param: [$pname]"
                #echo "value: [$pvalue]"
                $cfg_modules[$alias]["parameters"][$pname]=$pvalue
            }
        }
    }
    if ($tags){$cfg_modules[$alias]["tags"]=$tags.trim()}
    if ($thresholds){$cfg_modules[$alias]["thresholds"]=$thresholds.trim()}

    $parameters=$cfg_modules[$alias]["parameters"] -split ','


    ## Monitoring

    #Service Monitoring 
    if ($alias -match "(^Servicio$)" ){
        $servicename= $cfg_modules[$alias]["parameters"]["servicio"]
        #$servicename=$alias -replace "^Servicio_", ""
        $module_name=$modules_in_plugin["Servicio"]["module_name"] -replace "%nombre_servicio%", "$servicename"
        $module_type=$modules_in_plugin["Servicio"]["module_type"]
        $module_description=$modules_in_plugin["Servicio"]["module_description"] -replace "%nombre_servicio%", "$servicename"


        if(!$agent_data[$module_name]){
            $module_value=isServiceRunning "$servicename"
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }


        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
            
        }
    
    }


    # MSSQL Connectivity
    if ($alias -match "(^MSSQL_Conectividad$)" ){

        $instance= $cfg_modules[$alias]["parameters"]["instancia"]

        $module_name=$modules_in_plugin["MSSQL_Conectividad"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["MSSQL_Conectividad"]["module_type"]
        $module_description=$modules_in_plugin["MSSQL_Conectividad"]["module_description"] -replace "%instancia%", "$instance"
        if(!$agent_data[$module_name]){
            $module_value=SQLConnectivity (MSSQLInstance($instance))
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }    


        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }    

    }

     # MSSQL Metric Modules
    if ($alias -match "(^MSSQLQuery_UsuariosConectados$)" ){
        $instance= $cfg_modules[$alias]["parameters"]["instancia"]
        $module_name=$modules_in_plugin["MSSQLQuery_UsuariosConectados"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["MSSQLQuery_UsuariosConectados"]["module_type"]
        $module_description=$modules_in_plugin["MSSQLQuery_UsuariosConectados"]["module_description"] -replace "%instancia%", "$instance"
        if(!$agent_data[$module_name]){
            $module_value=SQLQueryMetric (MSSQLInstance($instance)) $modules_in_plugin["MSSQLQuery_ConexionesIniciadas"]["module_query"]
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }

        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }    
    }
     
    if ($alias -match "(^MSSQLQuery_ConexionesIniciadas$)" ){
        $instance= $cfg_modules[$alias]["parameters"]["instancia"]
        $module_name=$modules_in_plugin["MSSQLQuery_ConexionesIniciadas"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["MSSQLQuery_ConexionesIniciadas"]["module_type"]
        $module_description=$modules_in_plugin["MSSQLQuery_ConexionesIniciadas"]["module_description"] -replace "%instancia%", "$instance"
        if(!$agent_data[$module_name]){
            $module_value=SQLQueryMetric (MSSQLInstance($instance)) $modules_in_plugin["MSSQLQuery_ConexionesIniciadas"]["module_query"]
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }


        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }    
    }

    if ($alias -match "(^MSSQL_TamanoArchivosDatos$)" ){
        $instance= $cfg_modules[$alias]["parameters"]["instancia"]
        $module_name=$modules_in_plugin["MSSQL_TamanoArchivosDatos"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["MSSQL_TamanoArchivosDatos"]["module_type"]
        $module_description=$modules_in_plugin["MSSQL_TamanoArchivosDatos"]["module_description"] -replace "%instancia%", "$instance"
        
        # Instance Databases Sizes
        $dbsizes=SQLDBSizes (MSSQLInstance($instance))
        $module_name_tmp=$module_name
        $module_description_tmp=$module_description
        foreach($dbname in $dbsizes.Keys)
        {
                $module_name="$module_name_tmp ($dbname)"
                $module_description="$module_description_tmp ($dbname)"
 
                if(!$agent_data[$module_name]){
                    $module_value=$dbsizes.$dbname
                    $agent_data[$module_name]=$module_value
                    $broker_data[$module_name]=$module_value
                    }



                if ($isbroker -ne $false){
                    $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
                }else{
                    $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
                }    
        }


    }

    if ($alias -match "(^Contador_LatenciaBloqueos$)" ){

        $instance= $cfg_modules[$alias]["parameters"]["instancia"]
        $module_name=$modules_in_plugin["Contador_LatenciaBloqueos"]["module_name"] -replace "%instancia%", "$instance"
        $module_type=$modules_in_plugin["Contador_LatenciaBloqueos"]["module_type"]
        $module_description=$modules_in_plugin["Contador_LatenciaBloqueos"]["module_description"] -replace "%instancia%", "$instance"
        $counter=$modules_in_plugin["Contador_LatenciaBloqueos"]["module_counter"]
        
        if(!$agent_data[$module_name]){
            $module_value=SQLGetCounter "$counter"
            $agent_data[$module_name]=$module_value
            $broker_data[$module_name]=$module_value
        }



        if ($isbroker -ne $false){
            $xml_broker=Add_Module_xml $xml_broker "$module_name" "$module_type" $broker_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }else{
            $xml_agent=Add_Module_xml $xml_agent "$module_name" "$module_type" $agent_data[$module_name] "$module_description" $cfg_modules[$alias]["tags"]
        }    
    }
    #

}

function XMLOut{
    param([string]$xmldata,[string]$xmlfile)
    if (!$xmlfile){
        $xml_lines=$xmldata -split '\\n'
        foreach ($line in $xml_lines){
            if ($line -eq ""){continue}
            echo $line
       }
       return
    }


    $xml_lines=$xmldata -split '\\n'
    foreach ($line in $xml_lines){
        if ($line -eq ""){continue}
            echo $line
    }

}



XMLOut ("$xml_agent")


if ($xml_broker -ne ""){

    #$xml_broker_lines=$xml_broker -split '\\n'
    $now = $(get-date -f "yyyy-MM-dd HH:mm:ss")
    $brokername=$($env:COMPUTERNAME) + "_" + $brokersuffix
    $xml_outfile_broker=$xml_out_dir+"\"+$brokername

    echo "xml_outfile_broker $xml_outfile_broker"

    $os="Windows"
    $osversion=(Get-WmiObject Win32_OperatingSystem).Caption

    echo "--------------------"

    echo "<?xml version='1.0' encoding='UTF-8'?>\n"
    echo "<agent_data agent_name='$brokername' timestamp='$now' version='5.0' os='$os' os_version='$osversion' interval='300'>"

    XMLOut ("$xml_broker","$xml_outfile_broker")

    echo "</agent_data>"

}



exit









$sqlclusterresources=@()
$hostname=$env:computername
$PluginName="Plugin SQLServer PaaS"

$modules_prefix="SQLServer "

#$fileconfigs.GetEnumerator() | Sort-Object Name

$sqlinstances=$instances -split ','

$sqlinstances=CleanArraySpaces $sqlinstances


#$tags=CleanArraySpaces $tags

foreach ($instance in $sqlinstances) {

        # Get Service Status
        $module_name=$modules_prefix+"Service Status $instance"
        $module_type="generic_proc"
        $module_description="SQL Service Status for instance $instance - All other modules will not refresh if server is down."
        $module_value=SQLServiceInstanceRunning "$instance"
        
        Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
    
        # If Service is not running, don't check anything else 
        if ($module_value -eq 0){continue}

        # Get Service Status
        $module_name=$modules_prefix+"Agent Service Status $instance"
        $module_type="generic_proc"
        $module_description="SQL Agent Service Status for instance ${instance}."
        $module_value=SQLServiceAgentRunning "$instance"
        
        Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
    
        # If Service is not running, don't check anything else 
        #if ($module_value -eq 0){continue}


        # Obtain Cluster Resource Names instead of Hostnames for a Cluster Environment
        Try{
            Get-ClusterNode $hostname   -ErrorVariable getServiceError -ErrorAction SilentlyContinue| Get-ClusterResource | where-object {$_.ResourceType.name -eq "SQL Server Availability Group"}|foreach-object {
                $sqlclusterresources+= $_.Name
            }
        }
        Catch{
            $sqlclusterresources+= $hostname
        }

        #write-host "[$sqlclusterresources]"

        # Foreach SQL Group Resorce Running on this Node try to connect
        foreach ($sqlres in $sqlclusterresources) {
        
            # If instance is default instance just use NODE_NAME (non cluster) or RESOURCE_NAME\INSTANCE 
            if ($instance -like "MSSQLSERVER" -or $instance -like "*\MSSQLSERVER"){$serverinstance=$sqlres}else{$serverinstance=$sqlres + "\" + $instance }

            #write-host "-->[$serverinstance]"

            $module_name=$modules_prefix+"Connectivity to instance $instance"
            $module_type="generic_proc"
            $module_description="SQL Connectivity Status for instance ${instance}."
            $module_value=SQLConnectivity "$serverinstance" 
            
            Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

            # Metric Modules
            $module_name=$modules_prefix +"Connection Attempts $instance"
            $module_type="generic_data"
            $module_description="Number of total login attempts to the database"
            $module_value=SQLQueryMetric "$serverinstance" "select @@connections" "$module_name"

            Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"



            $module_name=$modules_prefix +"Total Connections $instance"
            $module_type="generic_data"
            $module_description="Number of total connections to instance databases"
            $module_value=SQLQueryMetric "$serverinstance" "SELECT COUNT(dbid) as Column1 FROM sys.sysprocesses WHERE dbid > 0" "$module_name"

            Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"



            # Instance Databases Sizes
            $dbsizes=SQLDBSizes "$serverinstance"
            foreach($dbname in $dbsizes.Keys)
            {
                $module_name=$modules_prefix +"$instance Database "+ $dbname
                $module_type="generic_data"
                $module_description="Size of Instance $instance Database $dbname in KB"
                $module_value=$dbsizes.$dbname

                Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

            }


        }



    
}


# Avoid Common Counter if cluster node does not own any SQL resource...
if ($sqlclusterresources.Count -ne 0){
# Common Counters for All Instances

# Lock Waits/sec
$module_name=$modules_prefix +"Lock Waits/sec ALL"
$module_type="generic_data"
$module_description="MSSQL_Average Wait Time"
$module_value=SQLGetCounter "\SQLServer:Locks(_total)\Lock Waits/sec"

Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

# Logins/sec
$module_name=$modules_prefix +"Logins/sec ALL"
$module_type="generic_data"
$module_description="MSSQL_General Statistics\Logins/sec"
$module_value=SQLGetCounter "\SQLServer:General Statistics\Logins/sec"

Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"


# TEST for 
#$module_name=$modules_prefix +"Workload Group Stats(internal)\CPU usage"
#$module_type="generic_data"
#$module_description="Workload Group Stats(internal)\CPU usage"
#$module_value=SQLGetCounter "\SQLServer:Workload Group Stats(internal)\CPU usage %"

#Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

}
