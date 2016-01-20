#!/usr/bin/perl

use POSIX qw(setsid strftime);
use File::Basename;
my $localdir = dirname(__FILE__);
my $scriptname=basename(__FILE__);

sub Usage {
	print "Pandora Events for Windows\n";
	print "$scriptname event_application event_severity event_module event_module_type event_module_data event_module_tags\n";
	exit;
}

if ($#ARGV == -1 or $ARGV[0] =~ "^\-h"){
	Usage();
}

my $PANDORA_CONFIGFILE="C:\\DATA\\SCRIPTS\\conf\\agent_config_sample.conf";
#my $PANDORA_TENTACLE_CLIENT="C:\\MONITORIZACION\\util\\tentacle_client.exe"
my $PANDORA_TENTACLE_CLIENT="C:\\DATA\\SCRIPTS\\util\\tentacle_client.exe";

my $hostname=`hostname`;
my $event_source = chomp($hostname);
my $event_application = $ARGV[0];
my $event_severity = $ARGV[1];
my $event_module = $ARGV[2];
my $event_module_type = $ARGV[3];
my $event_module_data = $ARGV[4];
my $event_module_tags = $ARGV[5];


my $XMLoutfile=$event_source.rand(1000).".data";

#Pandora Server And Agent
my ($pandora_server_ip,$pandora_server_port);


sub ReadConfig {
	my ($configvar,$configfile)=@_;
	my $configvarvalue="";
	if ( -e $configfile){
		open (FILE, "< $configfile") or die "ERROR: Can not read configfile '".$configfile."' for value '".$configvar."'";
		while(<FILE>){
			if(~/^$configvar /){
				my ($dummy,$value)=split(/ /,$_);
				chomp($value);
				$configvarvalue=$value;	
			}
		}
		return (0,$configvarvalue);
		close (FILE);	
	}else{
		return (1,"ERROR: Can not read configfile '".$configfile."' for value '".$configvar."'");
	}
}


sub WriteXML{
	my ($outfile,$event_source,$event_application,$event_severity,$event_module,$event_module_type,$event_module_data,$event_module_tags)=@_;
	my $now = strftime ("%Y-%m-%d %H:%M:%S", localtime());
	
	my $xmlheader = "<?xml version='1.0' encoding='UTF-8'?>\n";
	
	my $xmlagent_data_open= "<agent_data agent_name='$event_source' timestamp='$now' version='5.0' os='Other' os_version='N/A' interval='300'>\n";
	
	my $xmlmodule_data = "<module>\n";
	$xmlmodule_data .="<name>$event_module</name>\n";
	$xmlmodule_data .="<description><![CDATA[".$event_application." - ".$event_module."]]></description>\n";
	$xmlmodule_data .="<type>async_".$event_module_type."</type>\n";
	$xmlmodule_data .="<data>".$event_module_data."</data>\n";
	SWITCH:
	{
		if (lc($event_severity) eq "major" or $event_severity eq "critical"){$xmlmodule_data .="<str_critical><![CDATA[.*]]></str_critical>\n"; last SWITCH;}
		if (lc($event_severity) eq "warning"){$xmlmodule_data .="<str_warning><![CDATA[.*]]></str_warning>\n"; last SWITCH;}
	}
	$xmlmodule_data .="<tags><![CDATA[".$event_module_tags."]]></tags>\n";
	$xmlmodule_data .="</module>\n";
	
	my $xmlagent_data_close = "</agent_data>";
	
	
	open (OUTFILE, "> $outfile") or die "ERROR: Can not write XML data file '".$outfile."'";
	print OUTFILE $xmlheader.$xmlagent_data_open.$xmlmodule_data.$xmlagent_data_close;
	close (OUTFILE);
		
}


$pandora_server_ip=ReadConfig("server_ip",$PANDORA_CONFIGFILE);
$pandora_server_port=ReadConfig("server_port",$PANDORA_CONFIGFILE);

WriteXML($XMLoutfile,$event_source,$event_application,$event_severity,$event_module,$event_module_type,$event_module_data,$event_module_tags);

`$PANDORA_TENTACLE_CLIENT -v -a "$pandora_server_ip" -p "$pandora_server_port" "$XMLoutfile" 2 > NUL`;

if (! $?) {	unlink ($XMLoutfile);}

print "ERROR: Can not send XML data from $event_module ($event_application) to $pandora_server_ip:$pandora_server_port \n";

