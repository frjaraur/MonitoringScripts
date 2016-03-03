#!/bin/env perl
# V1.0
#
# Version V1.0 - Initial
#
my $VERSION="V1.0";

use warnings;
use strict;
use Getopt::Std;
use File::Basename;
my $me = basename($0);

#Apache:
#-          Apache: Porcentaje de CPU load
#-          Apache: Estadistica de accesos
#-          Apache: Estadistica request per second
#-          Apache: Estadistica requests KB/s per request.
#-          Apache: Estadistica request currently.
#-          Apache: Numero de procesos
#-          Apache: Estado de un virtualserver

sub Version(){
    print "$VERSION\n";
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


sub Round(){
    my $rounded = sprintf "%.0f", $_[0];
    return $rounded;
}


sub Usage(){
    print "Uso\n";
    print "$me <-c bbdd:user:passwd> [-u url_server-status] [-t tags] \n";
    print "-u url_server-status [default http[s]://localhost/server-status]\n";
    print "-t tag1,tag2,tag3\n";
	print "NOTE: Default Thresholds are hardcoded in perl hash %DEFAULT_THRESHOLDS\n";
    exit;
}

sub LinuxOsFlavour(){
	if ( -e "/etc/redhat-release" or -e "/etc/fedora-release"){return  "redhatlike";}
	if ( -e "/etc/lsb-release"){return "debianlike";}
	if ( -e "/etc/SuSE-release"){return "suselike";}
	return "unknown";
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
	$url=~s/(http|https)\:\/\///g;
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
		&CleanHTMLTags($_);
		
		#CPU Load # <dt>CPU Usage: u.89 s.14 cu0 cs0 - .00669% CPU load</dt>
		if($_ =~/CPU Usage:/i){
			my @t=split(/ - /,$_);@t=split(/ /,$t[1]);
			$dumm{"CPU Load"}{"value"}=$t[0];
			$dumm{"CPU Load"}{"type"}="generic_data";
		}
		#Total accesses and Traffic # <dt>Total accesses: 30 - Total Traffic: 117 kB</dt>
		if($_ =~/Total accesses:/i){
			my @t=split(/ - /,$_);
			foreach my $j (@t){
				my @t=split(/: /,$j);
				$dumm{$t[0]}{"value"}=$t[1];
				$dumm{$t[0]}{"type"}="generic_data_inc";
			}
		}
		#Requests #<dt>.00206 requests/sec - 8 B/second - 4002 B/request</dt>
		if($_ =~/requests\/sec/i){
			my @t=split(/ - /,$_);
			foreach my $j (@t){
				my @t=split(/ /,$j);
				$dumm{$t[1]}{"value"}=$t[0];
				$dumm{$t[1]}{"type"}="generic_data";
			}
		}
		#Requests #<dt>1 requests currently being processed, 4 idle workers</dt>
		if($_ =~/requests currently being proces/i){
			my @t=split(/, /,$_);
			foreach my $j (@t){
				my ($k,@t)=split(/ /,$j);
				$dumm{join(' ',@t)}{"value"}=$k;
				$dumm{join(' ',@t)}{"type"}="generic_data";
			}
		}
	}
	
	return %dumm;
}

sub CheckProcess(){
        my $process_name=$_[0];
        my $nproc=`ps -efwww|grep -v grep |grep '$process_name'|wc -l `;
        chomp($nproc);
        return $nproc;
}

########## DEFAULT THRESHOLDS ##########
my %DEFAULT_THRESHOLDS = ( #Warning, Criticald
    'requests/sec'    => [ 70,80 ],
    'Total accesses'        => [ 70,80 ],
    'CPU Load'        => [ 70,80 ],
    'requests currently being processed'        => [ 70,80 ],	
    'idle workers'    => [ 70,80 ],
    'B/request'    => [ 70,80 ],
	'Total Traffic'    => [ 70,80 ],
    'B/second'    => [ 70,80 ],	
);
#########################################






#### MAIN


our %opts;
getopts('vhu:t:', \%opts);
if ($opts{h}){Usage;}
if ($opts{v}){Version;}

our $statusurl="localhost/server-status";
if (defined($opts{u})){$statusurl=$opts{u};}

our $tags="";
$tags=$opts{t} if defined($opts{t});

#&XMLPrint("MySQL Server Process","generic_proc","MySQL Server Process",1,$tags);

my $linuxos=LinuxOsFlavour();
my $apacheprocess="apache ";
if ($linuxos =~/redh/ ){$apacheprocess="httpd ";}


if ( &CheckProcess($apacheprocess) == 0 ){&XMLPrint("Apache Server Process","generic_proc","Apache Server Process",0,$tags);exit 0;}
&XMLPrint("Apache Server Process","generic_proc","Apache Server Process",1,$tags);

my ($state,$statusstring)=&GetApacheStatus($statusurl);
my @lines=split(/\n/,$statusstring);
my %ApacheStatusValues=&GetApacheStatusValues(@lines);
foreach(keys %ApacheStatusValues){
	my $value=$ApacheStatusValues{$_}{"value"};
	# Clean metrics
	$value =~ tr/[A-Z][a-z] \%//d;
	#print "[$_] [".$value."]\n";
	&XMLPrint("Apache Server '$_'",$ApacheStatusValues{$_}{"type"},"Apache Server '$_'",$value,$tags,@{$DEFAULT_THRESHOLDS{$_}});
}


