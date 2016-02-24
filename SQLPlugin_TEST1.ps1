[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True)]
   [string]$cfgfile,
  [Parameter(Mandatory=$False)]
   [string]$clientsufix
)


function Usage {
    echo "Es imprescindible especificar el fichero de configuracion de instancias y un sufijo para el agente de la vista de cliente"
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
    $result=(Invoke-Sqlcmd -ServerInstance $instance -Query $query).Column1
    return $result
}

function SQLServiceInstanceRunning{
    param ([string]$instance)
    Get-Service | where-object { $_.DisplayName -match "SQL Server \($instance\)" } | foreach-object {if ($_.Status -ne "Running") { return 0 }}
    return 1
}


function GetConfigs{ # Read Configuration line by line from cfgfile
 param ([string]$cfgfile)
 $configs=@{}
 $instances=""
 $configlines = (Get-Content $cfgfile)
 foreach ($configline in $configlines) {
    if ($configline -like "^#*"){next}

    # One line for each instance ...
    #if ($configline -like "^INSTANCE*"){
    #    $dummy,$tmp=$configline -split ' '
    #    if ( $instances -like "" ){$instances=$tmp}else{$instances=$instances+","+$tmp}
    #    $configs.Set_Item("INSTANCES", $instances)
    #}
    $variable,$value=$configline -split ' '
    $configs.Set_Item("$variable", "$value")

 }

 #$configs.GetEnumerator() | Sort-Object Name
 return $configs
}


if ($help){ Usage }

#$configlines = (Get-Content $cfgfile)
$sqlclusterresources=@()
$hostname=$env:computername

$date=Get-Date -format "yyy-MM-dd HH:mm:ss"

$agent_name=$hostname+"_"+$clientsufix
$modules_prefix="SQLServer "

$fileconfigs=GetConfigs $cfgfile

#$fileconfigs.GetEnumerator() | Sort-Object Name

$sqlinstances=$fileconfigs.Get_Item("INSTANCES") -split ','

$tags=$fileconfigs.Get_Item("COMMON_TAGS") -split ','

$interval=$fileconfigs.Get_Item("COMMON_INTERVAL") -split ','

Agent_openxml "$agent_name" "$os" "$os_version" "$date" "$interval"

foreach ($instance in $sqlinstances) {
    #$instance
    #,$tmp=$configline -split ' '
    #echo $instance
    #$tags=$tmp -split ','


    # Service Status
    $module_name=$modules_prefix+"Service Status $instance"
    $module_type="generic_proc"
    $module_description="Returns the status of the SQL Instance $instance - If the instance is stopped, SQL monitoring will not continue."
    $module_value=SQLServiceInstanceRunning "$instance"
    foreach ($module_tag in $tags) {Module_xml "$module_name" "$module_type" "$module_value" "$module_description" "$module_tag"}
    
    # If Service is not running, don't check anything 
    if ($module_value -eq 0){next}

    # Obtain Cluster Resource Names
    Get-ClusterNode $hostname | Get-ClusterResource | where-object {$_.ResourceType.name -eq "SQL Server Availability Group"}|foreach-object {
        $sqlclusterresources+= ,$_.Name
    }

    # Foreach SQL Group Resorce Running on this Node try to connect
    foreach ($sqlres in $sqlclusterresources) {
        #echo $sqlres
        
        # If instance is default instance just use NODE_NAME (non cluster) or RESOURCE_NAME\INSTANCE 
        if ($instance -like "MSSQLSERVER"){$serverinstance=$sqlres}else{$serverinstance=$sqlres + "\" + $instance }


        # Metric Modules
        $module_name=$modules_prefix +"Connections $instance"
        $module_type="generic_data_inc"
        $module_description="Number of total login attempts to the database"
        $module_value=SQLQueryMetric "$serverinstance" "select @@connections" "$module_name"

        #echo "$module_name : [$module_value]"

        # Create XML data foreach tag
        foreach ($module_tag in $tags) {
            #echo $module_tag
            Module_xml "$module_name" "$module_type" "$module_value" "$module_description" "$module_tag"
        }
    }



    
}

Agent_closexml
