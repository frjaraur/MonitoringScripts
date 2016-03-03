#!/usr/bin/env perl
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

#MySQL:
#-          MySQL: Estado del proceso mysql_safe
#-          MySQL: % de memoria ocupada del proceso mysqld
#-          MySQL: Querys en cola.
#-          MySQL: Conectividad a una instancia
#
#
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

sub CheckProcess(){
        my $process_name=$_[0];
        my $nproc=`ps -efwww|grep -v grep |grep '$process_name'|wc -l `;
        chomp($nproc);
        return $nproc;
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

sub Usage(){
        print "Uso\n";
        print "$me <-c bbdd:user:passwd> [-t tags] \n";
        print "-c bbdd:user:passwd,bbdd1:user1:passwd1\n";
        print "-t tag1,tag2,tag3\n";
        exit;
}


########## DEFAULT THRESHOLDS ##########
my %DEFAULT_THRESHOLDS = ( #Warning, Critical
    'MemUsage'    => [ 80,90 ],
	# Queries per check interval (5min) Default Thresholds
    'Queries'        => [ 50,80 ],
);
#########################################


our %opts;
getopts('vhc:t:', \%opts);
if ($opts{h}){Usage;}
if ($opts{v}){Version;}
if (!defined($opts{c})){Usage;}

my @con=split(/,/,$opts{c});

our $tags="";
$tags=$opts{t} if defined($opts{t});


if ( &CheckProcess("mysqld_safe --basedir") != 1 ){&XMLPrint("MySQL Server Process","generic_proc","MySQL Server Process",0,$tags);exit 0;}
&XMLPrint("MySQL Server Safe Process","generic_proc","MySQL Safe Server Process",1,$tags);

my $memusage=&GetProcessMemoryPerctUsage("mysqld --basedir");
if ($memusage != 0){&XMLPrint("MySQL Server MemUsage","generic_data","MySQL Server MemUsage Percent", $memusage,$tags,@{$DEFAULT_THRESHOLDS{'MemUsage'}});}

if (!@con){Usage;}
foreach (@con){
        my ($host,$database,$username,$password)=split(/:/,$_ );
        my $constatus=&CheckConnectivity($host,$database,$username,$password);
        &XMLPrint("MySQL Server Connectivity $database","generic_proc","MySQL Server Connectivity $database",$constatus,$tags);
        if ($constatus != 1 ){next;}
        my ($stat,$value)=&CheckMYSQLStatusValue($host,$database,$username,$password,"Queries");
        if ($stat != 0){&XMLPrint("MySQL Server $database Queries","generic_data_inc","MySQL Server $database Queries", $value,$tags,@{$DEFAULT_THRESHOLDS{'Queries'}});}

}

