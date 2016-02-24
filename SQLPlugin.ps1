[CmdletBinding()]
Param(
  [Parameter(Mandatory=$False)]
   [string]$instances,
  [Parameter(Mandatory=$False)]
   [string]$tags,
  [Parameter(Mandatory=$False)]
   [switch]$help,
  [Parameter(Mandatory=$False)]
   [switch]$version
)

$VER="1.0"

#SQLServer
#          MSSQL Server: Conectividad con una instancia
#          MSSQL Server: Servicio MSSQL$INSTANCIA
#          MSSQL Server: Servicio SQLAgent$INSTANCIA
#          MSSQL Server:  Nº de Usuarios conectados
#          MSSQL Server: Tamaño (en kilobytes) de todos los archivos de datos
#          MSSQL Server: Latencia  para bloqueos
#          MSSQL Server: Nº  total de conexiones iniciadas







function Usage {
    $me=split-path $MyInvocation.PSCommandPath -Leaf
    echo "VERSION: $VER"
    echo "$me -instances $([char]34)HOSTNAME\INSTANCIA1,INSTANCIA2$([char]34) [-tags  $([char]34)TAG1,TAG2$([char]34)] [-help] [-version]"
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

function Agent_openxml {
	param ([string]$agent_name,[string]$os,[string]$os_version,[string]$date,[string]$interval)
	echo "<?xml version='1.0' encoding='UTF-8'?>";
	echo "<agent_data agent_name='$agent_name' timestamp='$date' version='5.0' os='Other' os_version='N/A' interval='$interval'>";


}

function Agent_closexml {
    echo "</agent_data>"
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


function SQLQueryMetric{
    param ([string]$instance,[string]$query,[string]$metric)
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
    $dummy,$ins=$instance -split '\\'


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
    $dummy,$ins=$instance -split '\\'


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




if ($help -or $instances -like "" -or $versio){ Usage }


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
        $module_description="Verificacion de estado del servicio SQL de la instancia $instance - No se ejecuta el resto de modulos si el servicio esta caido."
        $module_value=SQLServiceInstanceRunning "$instance"
        
        Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
    
        # If Service is not running, don't check anything else 
        if ($module_value -eq 0){continue}

        # Get Service Status
        $module_name=$modules_prefix+"Agent Service Status $instance"
        $module_type="generic_proc"
        $module_description="Verificacion de estado del servicio SQL Agent de la instancia ${instance}."
        $module_value=SQLServiceAgentRunning "$instance"
        
        Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"
    
        # If Service is not running, don't check anything else 
        if ($module_value -eq 0){continue}


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
                $module_description="Size of Instance's Database $dbname in KB"
                $module_value=$dbsizes.$dbname

                Module_xml  "$module_name" "$module_type" "$module_value" "$module_description" "$tags"

            }


        }



    
}

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
