#!/usr/bin/env perl
# V1.1
#
# Version V1.0 - Initial
# Version 1.1 - Added plugin configuration file
#
my $VER="V1.1";

use warnings;
use strict;
use Getopt::Std;
use File::Basename;
use File::Find;
use POSIX qw(setsid strftime);
use IO::Socket;

my $me = basename($0);
our $scriptname=$me;$scriptname=~s/\.pl$//g;
our $hostname=`hostname `;chomp($hostname);


## ENVIRONMENT - Change to accomplish real environment settings
our $TENTACLEOUTDIR="/tmp";
our $COLLECTIONSDIR="/tmp";


#Apache:
# Apache_Bytes/Sec
# Apache_BusyWorkers
# Apache_TotalAccesses
# Apache_IdleWorkers
# DISP_Proceso__field1_
# DISP_Apache__FIELD1__TCP__FIELD2_

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

sub CheckProcess(){ # Notice that this time we check for more than one process ... this could be managed with a new parameter 
					# allowing us to require a fixed number of process.
        my $process_name=$_[0];
        my $nproc=`ps -efwww|grep -v grep |grep '$process_name'|wc -l `;
        chomp($nproc);
		if ($nproc >= 1){
			return 1;
		}else{
			return 0;
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

sub TCPPortStatus{
	my ($host, $port)=@_;
	return 0 if ($port eq "");
	my $portstatus = IO::Socket::INET->new(
		Proto    => "tcp",
		PeerAddr => $host,
		PeerPort => $port,
		Timeout  => 8,
	);
	
	if ($portstatus) {return 1;}
	return 0;
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
	return ($os,$osversion);
}

sub CleanHTMLTags(){
	$_=~s/(<td>|<\/td>)//g;#$_=~s/\<\/td\>//g;
	$_=~s/(<dt>|<\/dt>)//g;
	$_=~s/(<tr>|<\/tr>)//g;
	#print "----------->$_\n";
	return $_;
}

sub CleanNonNumbers(){
	$_=~s/(\s+|(A-Z))//g;
	#$_=~tr/A-Z//cd;
	return $_;
}

sub GetApacheStatus(){
	my $url=$_[0];
	my $getter="";
	my $result="";
	GETTER:{
		if ( -e "/usr/bin/curl"){$getter="/usr/bin/curl --insecure";last GETTER;}
		if ( -e "/usr/bin/wget"){$getter="/usr/bin/wget --no-check-certificate -O -";last GETTER;}
	} 
	
	#Try https
	$result=`$getter https://$url 2>/dev/null`;
	if ($result ne ""){return (1,$result);}
	
	#Try http
	$result=`$getter http://$url 2>/dev/null`;
	if ($result ne ""){return (1,$result);}
	
	
	return (0,"nostatus");
}

sub GetApacheStatusValues(){
	my %dumm=();
	foreach(@_){
		chomp();
		&CleanHTMLTags($_);# Not required if we use 'auto' for status page
		my ($statusfield, $valuefield)=split(': ',$_);
		$dumm{"$statusfield"}=$valuefield; # Quite easy :P !
	}
	
	return %dumm;
}



############ MAIN

our $plugin_name="PaaS_APACHE_plugin_".$VER;

#Define all modules that could be created by this plugin
my %modules_in_plugin=(#alias => [type, module name, description]
	'Proceso' => {
		module_type => "generic_proc",
		module_name => "DISP_proceso %nombre_proceso%",
		module_description => "Proceso %nombre_proceso%"
		},	
	'Apache_BytesPerSec' => {
		module_type => "generic_data",
		module_name => "Apache_Bytes/Sec",
		module_description => "Apache_Bytes/Sec",
		module_apachestatusvalue => "BytesPerSec",
		},
	'Apache_BusyWorkers' => {
		module_type => "generic_data",
		module_name => "Apache_BusyWorkers",
		module_description => "Apache_BusyWorkers",
		module_apachestatusvalue => "BusyWorkers",
		},		
	'Apache_TotalAccesses' => {
		module_type => "generic_data",
		module_name => "Apache_TotalAccesses",
		module_description => "Apache_TotalAccesses",
		module_apachestatusvalue => "Total Accesses",
		},
	'Apache_IdleWorkers' => {
		module_type => "generic_data",
		module_name => "Apache_IdleWorkers",
		module_description => "Apache_IdleWorkers",
		module_apachestatusvalue => "IdleWorkers",
		},
	'Apache_Puerto' => {
		module_type => "generic_proc",
		module_name => "Apache_Puerto %puerto%",
		module_description => "Apache_Puerto %puerto%",
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

my $plugin_configfile=&GetConfigFile($COLLECTIONSDIR);


if ( ! -e $plugin_configfile){
    PluginError($plugin_name,"CRITICAL","ERROR: No se encontro el fichero $plugin_configfile");
}

# Tentacle Agent Output Dir
our $xml_out_dir=$TENTACLEOUTDIR;

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

our $statusurl="localhost/server-status?auto";

my ($state,$statusstring)=&GetApacheStatus($statusurl);
my @lines=split(/\n/,$statusstring);


our %ApacheStatusValues=&GetApacheStatusValues(@lines);


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

	
	# These monitoring steps could be done easier and sorter but taking same monitoring schema...
	# Apache_BytesPerSec Monitoring
    if ($alias eq "Apache_BytesPerSec"){
 		my $module_name=$modules_in_plugin{"Apache_BytesPerSec"}{"module_name"};
        my $module_type=$modules_in_plugin{"Apache_BytesPerSec"}{"module_type"};
		my $module_description=$modules_in_plugin{"Apache_BytesPerSec"}{"module_description"};
		
        if(!$agent_data{$module_name}){
            my $module_value=$ApacheStatusValues{"BytesPerSec"} // '';
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }	

	# Apache_BusyWorkers Monitoring
    if ($alias eq "Apache_BusyWorkers"){
 		my $module_name=$modules_in_plugin{"Apache_BusyWorkers"}{"module_name"};
        my $module_type=$modules_in_plugin{"Apache_BusyWorkers"}{"module_type"};
		my $module_description=$modules_in_plugin{"Apache_BusyWorkers"}{"module_description"};
		
        if(!$agent_data{$module_name}){
            my $module_value=$ApacheStatusValues{'BusyWorkers'} // '';
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }	
	
	# Apache_TotalAccesses Monitoring
    if ($alias eq "Apache_TotalAccesses"){
 		my $module_name=$modules_in_plugin{"Apache_TotalAccesses"}{"module_name"};
        my $module_type=$modules_in_plugin{"Apache_TotalAccesses"}{"module_type"};
		my $module_description=$modules_in_plugin{"Apache_TotalAccesses"}{"module_description"};
		
        if(!$agent_data{$module_name}){
            my $module_value=$ApacheStatusValues{'Total Accesses'} // '';
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }	

	# Apache_IdleWorkers Monitoring
    if ($alias eq "Apache_IdleWorkers"){
 		my $module_name=$modules_in_plugin{"Apache_IdleWorkers"}{"module_name"};
        my $module_type=$modules_in_plugin{"Apache_IdleWorkers"}{"module_type"};
		my $module_description=$modules_in_plugin{"Apache_IdleWorkers"}{"module_description"};
		
        if(!$agent_data{$module_name}){
            my $module_value=$ApacheStatusValues{'IdleWorkers'} // '';
            $agent_data{$module_name}=$module_value;
			$broker_data{$module_name}=$module_value;
        }

        if ($isbroker){
            $xml_broker=&Add_Module_xml($xml_broker,"$module_name","$module_type",$broker_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }else{
            $xml_agent=&Add_Module_xml($xml_agent,"$module_name","$module_type",$agent_data{$module_name},"$module_description",$cfg_modules{$alias}{"tags"},$thresholds);
        }

    }	
	
	
	# Apache Port
    if ($alias eq "Apache_Puerto"){
        my $host=$cfg_modules{$alias}{"parameters"}{"host"} // 'localhost';
		my $port=$cfg_modules{$alias}{"parameters"}{"puerto"} // '';
		my $module_name=$modules_in_plugin{"Apache_Puerto"}{"module_name"};
        $module_name=~s/\%puerto\%/\'$port\'/;
        my $module_type=$modules_in_plugin{"Apache_Puerto"}{"module_type"};
		my $module_description=$modules_in_plugin{"Apache_Puerto"}{"module_description"};
		$module_description=~s/\%puerto\%/\'$port\'/;
		
        if(!$agent_data{$module_name}){
            my $module_value=&TCPPortStatus($host, $port);
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
