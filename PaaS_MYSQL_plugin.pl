#!/usr/bin/env perl
# V1.1
#
# Version V1.0 - Initial
# Version 1.1 - Added plufin configuration file
#
my $VER="V1.1";

use warnings;
use strict;
use Getopt::Std;
use File::Basename;
use File::Find;
use POSIX qw(setsid strftime);

my $me = basename($0);
our $scriptname=$me;$scriptname=~s/\.pl$//g;
our $hostname=`hostname `;chomp($hostname);
#MySQL:
#-          MySQL: Estado del proceso mysql_safe
#-          MySQL: % de memoria ocupada del proceso mysqld
#-          MySQL: Querys en cola.
#-          MySQL: Conectividad a una instancia
#
#	
sub Version(){
        print "$VER\n";
        exit;
}

sub Usage(){
        print "Uso\n";
        print "$me [-l] [-v] \n";
        print "-l Lista todos los modulos generados por este plugin\n";
        exit;
}

sub XMLPrint(){
    my ($module_name,$module_type,$module_description,$module_data,$module_tags,$module_warning,$module_critical)=@_;
        my $xmlmodule_data = "<module>\n";
        $xmlmodule_data .="<name>$module_name</name>\n";
        $xmlmodule_data .="<description><![CDATA[".$module_description."]]></description>\n";
        $xmlmodule_data .="<type>".$module_type."</type>\n";
        if (defined($module_warning)){$xmlmodule_data .="<str_warning><![CDATA[$module_warning]]></str_warning>\n";}
        if (defined($module_critical)){$xmlmodule_data .="<str_critical><![CDATA[$module_critical]]></str_critical>\n";}
        $xmlmodule_data .="<data>".$module_data."</data>\n";
        $xmlmodule_data .="<tags><![CDATA[".$module_tags."]]></tags>\n";
        $xmlmodule_data .="</module>\n";
        print $xmlmodule_data;
}

sub CheckProcess(){
        my $process_name=$_[0];
        my $nproc=`ps -efwww|grep -v grep |grep '$process_name'|wc -l `;
        chomp($nproc);
		if ($nproc != 1){
			return 0;
		}else{
			return 1;
		}
}

sub CheckConnectivity(){
        my ($mysqlhost, $mysqldb, $mysqlusername, $mysqlpasswd)=@_;
        if ($mysqlusername eq "" or $mysqlpasswd eq ""){return 0;}
        $mysqlhost="-h$mysqlhost" if($mysqlhost ne "");
        $mysqldb="-D$mysqldb" if($mysqldb ne "");
        my $mysql_string="mysql $mysqlhost $mysqldb -u$mysqlusername -p$mysqlpasswd";
        open (MYSQLOUT,"$mysql_string -e 'SELECT 1 FROM DUAL' 2>&1| ");
        while (<MYSQLOUT>){
                chomp();
                if ($_=~/error/i or $_ eq "" ){return 0;}
        }
        return 1;
}

sub Round(){
        my $rounded = sprintf "%.0f", $_[0];
        return $rounded;
}

sub CheckMYSQLStatusValue(){
        my ($mysqlhost, $mysqldb, $mysqlusername, $mysqlpasswd, $param)=@_;
        my $value=0;
        if ($mysqlusername eq "" or $mysqlpasswd eq ""){return 0;}
        $mysqlhost="-h$mysqlhost" if($mysqlhost ne "");
        $mysqldb="-D$mysqldb" if($mysqldb ne "");
        my $mysql_string="mysql $mysqlhost $mysqldb -u$mysqlusername -p$mysqlpasswd";
        open (MYSQLOUT,"$mysql_string --batch --raw --silent --skip-column-names -e 'SHOW GLOBAL STATUS LIKE \"$param\";' 2>&1 | ");
        while (<MYSQLOUT>){
                chomp();
                if ($_=~/error/i or $_ eq "" ){return (0,$value);}
                my @dummy=split(/\s+/, $_);
                $value=$dummy[1];
        }
        return (1,$value);
}

sub GetProcessMemoryPerctUsage(){
        my $memusage=0;
        my $process_name=$_[0];
        open (PROCS,"ps aux | grep -v 'grep' | grep '$process_name'  | ");
        while (<PROCS>){
                chomp();
                my @dummy=split(/\s+/, $_);
                $memusage=$dummy[3] + $memusage;
        }
        return &Round($memusage);
}

sub GetProcesCPUPerctUsage(){
        my $cpuusage=0;
        my $process_name=$_[0];
        open (PROCS,"ps aux | grep -v 'grep' | grep '$process_name'  | ");
        while (<PROCS>){
                chomp();
                my @dummy=split(/\s+/, $_);
                $cpuusage=$dummy[2] + $cpuusage;
        }
        return &Round($cpuusage);
}


sub GetConfigFile{
	my $confiddir=$_[0];
	my $configfilename=$scriptname.".".$hostname.".cfg";
	my @files;
	my $configfile;
	find(sub {push @files,$File::Find::name if (-f $File::Find::name and /$configfilename$/);}, $confiddir);
	$configfile=$files[0];
	if (!$configfile){$configfile=$confiddir."/".$scriptname.".cfg"}
    return $configfile;
}

sub PluginError{
    my ($plugin,$severity,$text)=@_;
	print "<module>\n";
	print "<name><![CDATA[$plugin]]></name>\n";
	print "<type>generic_data_string</type>\n";
	print "<description><![CDATA[Plugin Execution Status]]></description>\n";
	print "<data><![CDATA[${severity}: $text]]></data>\n";
    #echo "<tags><![CDATA[$module_tags]]></tags>"
	print "<str_critical><![CDATA[CRITICAL:]]></str_critical>\n";
	print "<str_warning><![CDATA[WARNING:]]></str_warning>\n";
	print "</module>\n";
    exit;
}

sub Add_Module_xml {
	my ($xmldata,$module_name,$module_type,$module_value,$module_description,$module_tags,$module_thresholds)=@_;

	$xmldata= "$xmldata<module>";
    $xmldata="$xmldata\n<name><![CDATA[$module_name]]></name>";
	$xmldata="$xmldata\n<type>$module_type</type>";
	$xmldata="$xmldata\n<description><![CDATA[$module_description]]></description>";


    if($module_thresholds){
        my ($warn,$crit)=split(/,/,$module_thresholds);
        $xmldata="$xmldata\n<str_warning><![CDATA[$warn]]></str_warning>";
        $xmldata="$xmldata\n<str_critical><![CDATA[$crit]]></str_critical>";
    }

    $xmldata="$xmldata\n<data><![CDATA[$module_value]]></data>";
    $xmldata="$xmldata\n<tags><![CDATA[$module_tags]]></tags>";

	$xmldata="$xmldata\n</module>\n";

    return $xmldata;

}

sub MySQLQueryValue(){
        my ($mysqlhost, $mysqldb, $mysqlusername, $mysqlpasswd, $query)=@_;
        my $value=0;
        if ($mysqlusername eq "" or $mysqlpasswd eq ""){return 0;}
        $mysqlhost="-h$mysqlhost" if($mysqlhost ne "");
        $mysqldb="-D$mysqldb" if($mysqldb ne "");
        my $mysql_string="mysql $mysqlhost $mysqldb -u$mysqlusername -p$mysqlpasswd";
        open (MYSQLOUT,"$mysql_string --batch --raw --silent --skip-column-names -e \"$query;\" 2>&1 | ");
        while (<MYSQLOUT>){
                chomp();
                if ($_=~/error/i or $_ eq "" ){return (0,$value);}
                my @dummy=split(/\s+/, $_);
                $value=$dummy[1];
        }
        return (1,$value);
}

sub XMLOut{
    my($xmldata,$xmlfile,$brokername,$os,$osversion)=@_;
    my @xml_lines=split('\\n',$xmldata);

    # Write plugin xml modules data to OUTPUT for Agent
    if (!$xmlfile){
       print $xmldata;
       return;
    }

    # Write plugin xml modules data to file for Broker
    # We need to know date for agent header...
    my $now = strftime ("%Y-%m-%d %H:%M:%S", localtime());
    open(XMLBROKERFH,">$xmlfile");
	print XMLBROKERFH "<?xml version='1.0' encoding='UTF-8'?>";
    print XMLBROKERFH "<agent_data agent_name='".$brokername."' timestamp='".$now."' version='5.0' os='".$os."' os_version='".$osversion."' interval='300'>";
	print XMLBROKERFH $xmldata;
   # foreach ($line in $xml_lines){
        # if ($line -eq ""){continue}
            # $stream.WriteLine($line)
    # }
    print XMLBROKERFH "</agent_data>";
    close XMLBROKERFH;
}

sub GetOS{
	my $os=$^O;
	my $osversion="unknown";
	my @osfiles=("/etc/redhat-release","/etc/debian_version","/etc/lsb-release","/etc/SuSE-release");
	foreach(@osfiles){
		if ( -e $_ ){ 
				open my $osfile, "<$_"; 
				$osversion = <$osfile>;
				chomp($osversion);
				close $osfile;
				last;
			}
	}
	# OSVERSION:{
		# if ( -e "/etc/redhat-release" ){ 
			# open my $osfile, "</etc/redhat-release"; 
			# $osversion = <$osfile>;
			# chomp($osversion);
			# close $osfile;
			# last OSVERSION;
		# }
		# if ( -e "/etc/debian_version" ){ 
			# open my $osfile, "</etc/debian_version"; 
			# $osversion = <$osfile>;
			# chomp($osversion);
			# close $osfile;
			# last OSVERSION;
		# }
		# if ( -e "/etc/lsb-release" ){ 
			# open my $osfile, "</etc/lsb-release"; 
			# $osversion = <$osfile>;
			# chomp($osversion);
			# close $osfile;
			# last OSVERSION;
		# }		
		# if ( -e "/etc/SuSE-release" ){ 
			# open my $osfile, "</etc/SuSE-release"; 
			# $osversion = <$osfile>;
			# chomp($osversion);
			# close $osfile;
			# last OSVERSION;
		# }
	# }
	
	return ($os,$osversion);
}

############ MAIN

our $plugin_name="PaaS_MySQL_plugin_".$VER;

#Define all modules that could be created by this plugin
my %modules_in_plugin=(#alias => [type, module name, description]
	'Proceso' => {
		module_type => "generic_proc",
		module_name => "DISP_proceso %nombre_proceso%",
		module_description => "Proceso %nombre_proceso%"
		},
	'MemProceso' => {
		module_type => "generic_data",
		module_name => "DISP_memoria %nombre_proceso%",
		module_description => "Uso memoria %nombre_proceso%"
		},
	'CPUProceso' => {
		module_type => "generic_data",
		module_name => "DISP_cpu %nombre_proceso%",
		module_description => "Uso CPU %nombre_proceso%"
		},		
	'MySQL_Conectividad' => {
		module_type => "generic_proc",
		module_name => "MySQL: Conectividad a instancia %instancia%",
		module_description => "MySQL: Conectividad a instancia %instancia%"
		},
	'MySQL_SlowQueries' => {
		module_type => "generic_data",
		module_name => "MySQL_SlowQueries %basedatos%",
		module_description => "MySQL_SlowQueries %basedatos%",
		module_querystring => "show status like 'slow_queries'",
		},
	'MySQL_SlaveStatus' => {
		module_type => "generic_data",
		module_name => "MySQL_SlaveStatus %basedatos%",
		module_description => "MySQL_SlaveStatus %basedatos%",
		module_querystring => "show status like 'Slow_queries'",
		module_searchpattern => "Slave.*Running",
		},
);

my %opts;
getopts('vhl', \%opts);
if ($opts{h}){Usage;}
if ($opts{v}){Version;}



# List All available modules that this plugin could check
if ($opts{l}){
    my @arr_modules_in_plugin = keys(%modules_in_plugin);
    foreach my $a (@arr_modules_in_plugin){
        print "\n$a\n";
        foreach my $k (keys(%{$modules_in_plugin{$a}})){
            print "\t$k\t->\t $modules_in_plugin{$a}{$k}\n";
        }
    }
    exit
}

my $plugin_configfile=&GetConfigFile("/tmp");


if ( ! -e $plugin_configfile){
    PluginError($plugin_name,"CRITICAL","ERROR: No se encontro el fichero $plugin_configfile");
}

# Tentacle Agent Output Dir
our $xml_out_dir="/tmp";

# Configuration for modules from configfile
my %cfg_modules;

# Agent
our $xml_agent;
my %agent_data;

# Broker
our $brokersuffix="SALUD";
our $xml_broker;
my %broker_data;
# Theses data is needed jut in case of broker agent
our $brokername=$hostname."_".$brokersuffix;
our ($os,$osversion)=GetOS();

open(CFGFH,"<$plugin_configfile") or PluginError($plugin_name,"CRITICAL","ERROR: No se leer el fichero $plugin_configfile");

while(<CFGFH>){

    #Avoid Comments or Empty Lines
    if($_ =~/^#/ or $_ eq "" ){next;}
	
	chomp();

    # Initiate configuration Fields comma delimited by '||' (two pipes)
    my ($alias, $isbroker, $parameters, $tags, $thresholds)=split('\|\|',$_); 

    # Avoid left and rigth spaces in alias (spaces at both sides are allowed for better reading)
    $alias=~s/^\s+|\s+$//g;
	
    # Create an empty table/hash for this check from file
    my %cfg_modules;

    # Give name for this "configuration line"
    $cfg_modules{$alias}{"alias"}=$alias;

    # Check if exists isbroker field
    if ($isbroker){
		$isbroker=~ s/^\s+|\s+$//g;
		if ($isbroker eq "" && uc($isbroker) ne "TRUE"){undef($isbroker);}
    }

    # Thresholds
    if(!$thresholds){$thresholds="";}	

	# Take parameters from configuration and sepaparate them into param=value with ',' as delimiter
    if ($parameters){
        $parameters=~s/^\s+|\s+$//g;
        my @arrparameters=split(',',$parameters);
		foreach my $paramline (@arrparameters){
			my ($pname,$pvalue)=split('=',$paramline);
			$cfg_modules{$alias}{"parameters"}{$pname}=$pvalue;
		}
    }
    if ($tags){$tags=~s/^\s+|\s+$//g;$cfg_modules{$alias}{"tags"}=$tags;}
    if ($thresholds){$thresholds=~s/^\s+|\s+$//g;$cfg_modules{$alias}{"thresholds"}=$thresholds;}
	
	
    ## Monitoring
    #
    # Every configured check in file is done just one time and value is added for agent and for broker too, this way both have same value even it is needed or not
    #

    #Process Monitoring
    if ($alias eq "Proceso" ){

        my $process=$cfg_modules{$alias}{"parameters"}{"proceso"};
		my $module_name=$modules_in_plugin{"Proceso"}{"module_name"};
        $module_name=~s/\%nombre_proceso\%/\'$process\'/;
        my $module_type=$modules_in_plugin{"Proceso"}{"module_type"};
		my $module_description=$modules_in_plugin{"Proceso"}{"module_description"};
		$module_description=~s/\%nombre_proceso\%/\'$process\'/;
		
        if(!$agent_data{$module_name}){
            my $module_value=&CheckProcess("$process");
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }
	
	
	
	#Memory Monitoring
    if ($alias eq "Memoria"){
        my $process=$cfg_modules{$alias}{"parameters"}{"proceso"};
		my $module_name=$modules_in_plugin{"MemProceso"}{"module_name"};
        $module_name=~s/\%nombre_proceso\%/\'$process\'/;
        my $module_type=$modules_in_plugin{"MemProceso"}{"module_type"};
		my $module_description=$modules_in_plugin{"MemProceso"}{"module_description"};
		$module_description=~s/\%nombre_proceso\%/\'$process\'/;
		
        if(!$agent_data{$module_name}){
            my $module_value=&GetProcessMemoryPerctUsage("$process");
			print ">$module_value<\n";
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }


	#CPU Monitoring
    if ($alias eq "CPUProceso"){
        my $process=$cfg_modules{$alias}{"parameters"}{"proceso"};
		my $module_name=$modules_in_plugin{"CPUProceso"}{"module_name"};
        $module_name=~s/\%nombre_proceso\%/\'$process\'/;
        my $module_type=$modules_in_plugin{"CPUProceso"}{"module_type"};
		my $module_description=$modules_in_plugin{"CPUProceso"}{"module_description"};
		$module_description=~s/\%nombre_proceso\%/\'$process\'/;
		
        if(!$agent_data{$module_name}){
            my $module_value=&GetProcesCPUPerctUsage("$process");
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }	

	#MySQL SlowQueries Monitoring
    if ($alias eq "MySQL_SlowQueries"){
        my $mysqldb=$cfg_modules{$alias}{"parameters"}{"bbdd"} // '';
		my $module_name=$modules_in_plugin{"MySQL_SlowQueries"}{"module_name"};
        $module_name=~s/\%basedatos\%/\'$mysqldb\'/;
        my $module_type=$modules_in_plugin{"MySQL_SlowQueries"}{"module_type"};
		my $module_description=$modules_in_plugin{"MySQL_SlowQueries"}{"module_description"};
		$module_description=~s/\%basedatos\%/\'$mysqldb\'/;
		
        if(!$agent_data{$module_name}){
			#($mysqlhost, $mysqldb, $mysqlusername, $mysqlpasswd, $query)
			my $mysqlhost=$cfg_modules{$alias}{"parameters"}{"host"} // '';
			my $mysqlusername=$cfg_modules{$alias}{"parameters"}{"username"};
			my $mysqlpasswd=$cfg_modules{$alias}{"parameters"}{"password"};
			my $query=$modules_in_plugin{"MySQL_SlowQueries"}{"module_querystring"};
            my $module_value=&MySQLQueryValue($mysqlhost, $mysqldb, $mysqlusername, $mysqlpasswd, $query);
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }	

}



# Checks from configuration file are done... so print their results

# For Agent just print OUT xml module tags
XMLOut($xml_agent);

# If there is any data for broken agent create a file with all its xml module tags and agent headers/end
if ($xml_broker ne ""){

    # Filename will be created using a random float number between 0 and 1000 (we replace decimal symbol if needed...) and brokername
    my $randomseed=rand(1000);
    my $xml_outfile_broker=$xml_out_dir."/".$brokername.$randomseed.".data";

    # For broken agent print xml modules in file for tentacle
    XMLOut($xml_broker,$xml_outfile_broker,$brokername,$os,$osversion);
}
