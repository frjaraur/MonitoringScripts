
#!/bin/env perl
#
use warnings;
use strict;

#MySQL:
#-          MySQL: Estado del proceso mysql_safe
#-          MySQL: % de memoria ocupada del proceso mysqld
#-          MySQL: Querys en cola.
#-          MySQL: Conectividad a una instancia

sub XMLPrint(){
    print "@_\n";
    my ($module_name,$module_type,$module_description,$module_data,$module_tags)=@_;
        my $xmlmodule_data = "<module>\n";
        $xmlmodule_data .="<name>$module_name</name>\n";
        $xmlmodule_data .="<description><![CDATA[".$module_description."]]></description>\n";
        $xmlmodule_data .="<type>".$module_type."</type>\n";
        #$xmlmodule_data .="<str_critical><![CDATA[CRITICAL:]]></str_critical>\n";
        #$xmlmodule_data .="<str_warning><![CDATA[WARNING:]]></str_warning>\n";
        $xmlmodule_data .="<data>".$module_data."</data>\n";
        $xmlmodule_data .="<tags><![CDATA[".$module_tags."]]></tags>\n";

        # Instructions ...

        #INSTRUCTIONS:
        #{
                #if ($event_instructions eq ""){last INSTRUCTIONS;}
                #if (lc($event_severity) eq "major" or $event_severity eq "critical"){$xmlmodule_data .="<critical_instructions><![CDATA[".$event_instructions."]]></critical_instructions>\n"; last INSTRUCTIONS;}
                #if (lc($event_severity) eq "warning"){$xmlmodule_data .="<warning_instructions><![CDATA[".$event_instructions."]]></warning_instructions>\n";last INSTRUCTIONS;}
        #}

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
        my ($mysqlhost, $mysqlusername, $mysqlpasswd, $mysqldb)=@_;
        if ($mysqlusername eq "" or $mysqlpasswd eq ""){return 0;}
        $mysqlhost="-h$mysqlhost" if($mysqlhost ne "");
        $mysqldb="-D$mysqldb" if($mysqldb ne "");
        my $mysql_string="mysql $mysqlhost $mysqldb -u$mysqlusername -p$mysqlpasswd";
        open (MYSQLOUT,"$mysql_string -e 'SELECT 1 FROM DUAL' 2>/dev/null | ");
        while (<MYSQLOUT>){
                chomp();
                if ($_=~/error/i){return 0;}
        }
        return 1;
}

sub Round(){
        my $rounded = sprintf "%.0f", $_[0];
        return $rounded;
}

sub CheckMySQLValue(){
        my ($mysqlhost, $mysqlusername, $mysqlpasswd, $mysqldb, $query)=@_;
        my $value=0;
        if ($mysqlusername eq "" or $mysqlpasswd eq ""){return 0;}
        $mysqlhost="-h$mysqlhost" if($mysqlhost ne "");
        $mysqldb="-D$mysqldb" if($mysqldb ne "");
        my $mysql_string="mysql $mysqlhost $mysqldb -u$mysqlusername -p$mysqlpasswd";
        open (MYSQLOUT,"$mysql_string --batch --raw --silent --skip-column-names -e '$query;' 2>/dev/null | ");
        while (<MYSQLOUT>){
                chomp();
                if ($_=~/error/i){return (0,$value);}
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



our $DEFAULT_MEMUSAGE_WARNING=70;
our $DEFAULT_MEMUSAGE_CRITICAL=90;
our $tags="";

if ( &CheckProcess("mysqld --basedir") != 1 ){&XMLPrint("MySQL Server Process","generic_proc","MySQL Server Process",0,$tags);exit 0;}
&XMLPrint("MySQL Server Process","generic_proc","MySQL Server Process",1,$tags);

if (&CheckConnectivity("","pandora","00pandora00","pandora") != 1){&XMLPrint("MySQL Server Connectivity","generic_proc","MySQL Server Connectivity",0,$tags);exit 0;}
&XMLPrint("MySQL Server Connectivity","generic_proc","MySQL Server Connectivity",1,$tags);

my ($stat,$value)=&CheckMySQLValue("","pandora","00pandora00","pandora","SHOW GLOBAL STATUS LIKE \"Queries\"");
if ($stat != 0){
        &XMLPrint("CRITICAL:", $value);

}

my $memusage=&GetProcessMemoryPerctUsage("mysqld --basedir");

MEMUSAGE:{

        if ($memusage >= $DEFAULT_MEMUSAGE_CRITICAL ){&XMLPrint("CRITICAL:", "Consumo supera critical.");last MEMUSAGE; }
        if ($memusage >= $DEFAULT_MEMUSAGE_WARNING ){&XMLPrint("WARNING:", "Consumo supera warning.");last MEMUSAGE; }
        &XMLPrint("OK:", "Consumo ok.");last MEMUSAGE;
}

