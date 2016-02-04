#!/bin/env perl
use strict;
use warnings;
use Time::HiRes qw(gettimeofday tv_interval);
use WWW::Selenium;
use URI;
use Data::Dumper;


use Getopt::Long qw(GetOptions);
use POSIX qw(setsid strftime);
use File::Basename;
use threads;

my $scriptname=basename(__FILE__);

# DEFAULTS:
our $nproc = 3;
our $SHost = 'localhost';
our $SPort = 4444;
our $SBrowser = '*iexplore';
our $SDomain="about:blank";
our $Tasksfile ="";
our $MAXLOGFILES=2;
our $MAXLOGFILESIZE=10; #MB
our $PANDORA_LOGDIR="C:\\MONITORIZACION\\log";
our $PANDORA_SPOOLDIR="C:\\MONITORIZACION\\temp";
our $LOGFILE=$PANDORA_LOGDIR."\\".$scriptname.".log";
our $currenttime=strftime "%Y-%m-%d %H:%M:%S", localtime;
our $DEBUG=0;

#Check For Some required files and dirs to work...
# DIRS
my @required_dirs=($PANDORA_SPOOLDIR,$PANDORA_LOGDIR);
foreach (@required_dirs){
	if ( ! -d $_){ ErrorInfo ($currenttime,"ERROR: Does not exist required dir ".$_);}	
}


LogfileMaintenance($LOGFILE, $MAXLOGFILES,$MAXLOGFILESIZE);


my $Debug;
GetOptions(
    'host=s' => \$SHost,
	'port=i' => \$SPort,
	'browser=s' => \$SBrowser,
	'tasksfile=s' => \$Tasksfile,
    'debug' => \$DEBUG,
) or Usage($scriptname);

Usage($scriptname) if ($Tasksfile eq "");


if ( ! -e $Tasksfile ){ ErrorInfo ($currenttime,"ERROR: Does not exist required tasksfile ".$Tasksfile);}
my %tasks_in_file=ReadTasksFile($Tasksfile);

my @all_tasks_packaged=TasksPackages($nproc,keys %tasks_in_file);

#print scalar(keys %tasks_in_file);

#print @all_tasks_packaged;

LoggingInfo ($currenttime,"We found ".scalar(keys %tasks_in_file)." tasks in $Tasksfile ") if ($DEBUG ne 0);

if (scalar(keys %tasks_in_file) >= $nproc){
	my $i=0;
	my @th;
	foreach my $arraypackage (@all_tasks_packaged){
		#print "\n[$i] $arraypackage\n";
		push @th, threads->new(\&ExecuteTaskPackage,@{$arraypackage});

	}
	$_->join for @th;


}else{

	foreach my $t(keys %tasks_in_file){
		LoggingInfo ($currenttime,"Executing TaskName: $t") if ($DEBUG ne 0);
		ExecuteTask(@{$tasks_in_file{$t}});
	}
}



## Functions


sub DummyExecuteTaskPackage{
	my $tid = threads->tid();
	print "Thread ID: [$tid]\n";
	foreach my $task (@_){
		print "task: $task\n";
		
	}
	sleep 5;
}


sub Usage{
	print "Usage $_";
	exit;

}


sub LogfileMaintenance{
    my ($logfile, $numberoffiles,$maxlogfilesize)=@_;
    if ( ! -e $logfile ){ return 1;}
    my $logfilesize = -s $logfile;
    $maxlogfilesize=$maxlogfilesize*1024*1024;
    if  ($logfilesize >= $maxlogfilesize){
    	for (my $count = $numberoffiles; $count > 1; $count--) {
        	my $tmpcount=$count-1;
            if ( -e $logfile.".".$tmpcount ) {rename ($logfile.".".$tmpcount, $logfile.".".$count);}
         }
         rename ($logfile, $logfile.".1");
    }
    return 1;
}


sub ErrorInfo{
	my $currenttime = $_[0];
	my $debuginfo_text="$currenttime +++ ".$_[1]."\n";
	print $debuginfo_text;
	open LOGFILE, ">>$LOGFILE" or die "ERROR: No es posible escribir en el fichero de log ".$LOGFILE.".";
	print LOGFILE "ERROR: $debuginfo_text";
	close LOGFILE;
	exit 1;
}

sub LoggingInfo{
	my $currenttime=$_[0];
	my $debuginfo_text="$currenttime +++ ".$_[1]."\n";
	if ($DEBUG != 0 ) {print $debuginfo_text;}
	open LOGFILE, ">>$LOGFILE" or die "ERROR: No es posible escribir en el fichero de log ".$LOGFILE.".";
	print LOGFILE "LOGGING: $debuginfo_text";
	close LOGFILE;
}

sub ReadTasksFile{
	my %tasks;
	my $taskname="";
	my $taskfile=$_[0];

	open (TASKSFILE, "< $taskfile") or ErrorInfo ($currenttime,"ERROR: Can not read tasksfile '".$taskfile."' ....");
	my $read=0;
	my $count=1;
	while(<TASKSFILE>){
		chomp $_;
		if($_=~/^#/ or $_ eq ""){next;}
		if($_=~/^\s*task_begin\s+(.*)/){
			$read=1;my @dummy=split(/ /,$_);
			$taskname=$dummy[1];
			$tasks{$taskname}=();
			$count++;
			LoggingInfo ($currenttime,"TaskName: $taskname") if ($DEBUG ne 0);
			next;
			}
		if($_=~/^\s*task_end/){$read=0;next; undef $taskname}
		if ($read != 0 ){push (@{$tasks{$taskname}}, $_);}
		LoggingInfo ($currenttime,"Reading tasks $_") if ($DEBUG ne 0 and $read != 0);
	}
	close (TASKSFILE);

	
	return %tasks;
}

sub ExecuteTaskOneByOne{
	my ($Selenium,$command,@parameters)=@_;
	my ($SeleniumText,$SeleniumCapture,$SeleniumExecutionExit,$SeleniumCookie)=();
	
	
	EXECUTIONS:
	{
		# Answer on next prompt
		if ($command eq "answer_on_next_prompt") {$Selenium->answer_on_next_prompt(@parameters);last EXECUTIONS;}
		# Attach file
		if ($command eq "attach_file") {$Selenium->attach_file(@parameters);last EXECUTIONS;}
		# Capture entire page screenshot
		if ($command eq "capture_entire_page_screenshot") {$Selenium->capture_entire_page_screenshot(@parameters, '');last EXECUTIONS;}
		# Capture entire page screenshot to string
		if ($command eq "capture_entire_page_screenshot_to_string") {$SeleniumCapture = $Selenium->capture_entire_page_screenshot_to_string('');last EXECUTIONS;}
		# Check
		if ($command eq "check") {$Selenium->check(@parameters);last EXECUTIONS;}
		# Choose cancel on next confirmation
		if ($command eq "choose_cancel_on_next_confirmation") {$Selenium->choose_cancel_on_next_confirmation();last EXECUTIONS;}
		# Click
		if ($command eq "click") {$Selenium->click(@parameters);last EXECUTIONS;}
		# Close
		if ($command eq "close") {$Selenium->close();last EXECUTIONS;}
		# Create cookie
		if ($command eq "create_cookie") {$Selenium->create_cookie(@parameters);last EXECUTIONS;}
		# Delete all visible cookies
		if ($command eq "delete_all_visible_cookies") {$Selenium->delete_all_visible_cookies();last EXECUTIONS;}
		# Delete cookie
		if ($command eq "delete_cookie") {$Selenium->delete_cookie(@parameters);last EXECUTIONS;}
		# Double click
		if ($command eq "double_click") {$Selenium->double_click(@parameters);last EXECUTIONS;}
		# Focus
		if ($command eq "focus") {$Selenium->focus(@parameters);last EXECUTIONS;}
		# Get attribute
		if ($command eq "get_attribute") {$SeleniumText = $Selenium->get_attribute(@parameters);last EXECUTIONS;}
		# Get body text
		if ($command eq "get_body_text") {$SeleniumText = $Selenium->get_body_text();last EXECUTIONS;}
		# Get body text (regexp)
		if ($command eq "get_body_text") {
			my $SeleniumSearchPattern ="";$SeleniumSearchPattern= join($SeleniumSearchPattern, @parameters);
			my $SeleniumText = $Selenium->get_body_text();
			if ($SeleniumText !~ $SeleniumSearchPattern){$SeleniumExecutionExit=1};
			last EXECUTIONS;
		}
		# Get cookie by name
		if ($command eq "get_cookie_by_name") {$SeleniumCookie=$Selenium->get_cookie_by_name(@parameters);last EXECUTIONS;}
		# Get HTML source
		if ($command eq "get_html_source") {$SeleniumText =$Selenium->get_html_source();last EXECUTIONS;}
		# Get HTML source (regexp)
		if ($command =~ /^\s*get_html_source\s+(.*)/) {
			my $SeleniumSearchPattern ="";$SeleniumSearchPattern= join($SeleniumSearchPattern, @parameters);
			my $SeleniumText = $Selenium->get_html_source();
			if ($SeleniumText !~ $SeleniumSearchPattern){$SeleniumExecutionExit=1};
			last EXECUTIONS;
		}
		# Get location
		if ($command eq "get_location") {$SeleniumText = $Selenium->get_location();last EXECUTIONS;}
		# Get text
		if ($command eq "get_text") {$SeleniumText = $Selenium->get_text(@parameters);last EXECUTIONS;}
		# Get table
		if ($command eq "get_table") {$SeleniumText = $Selenium->get_table(@parameters);last EXECUTIONS;}
		# Get title
		if ($command eq "get_title") {$SeleniumText = $Selenium->get_title();last EXECUTIONS;}
		# Get value
		if ($command eq "get_value"){$SeleniumText = $Selenium->get_value(@parameters);last EXECUTIONS;}
		# Go back
		if ($command eq "go_back") {$Selenium->go_back();}
		# Is cookie present
		if ($command eq "is_cookie_present") {if (! $Selenium->is_cookie_present(@parameters)){$SeleniumExecutionExit=1};last EXECUTIONS;}
		# Is editable
		if ($command eq "is_editable") {if (! $Selenium->is_editable(@parameters)){$SeleniumExecutionExit=1};last EXECUTIONS;}
		# Is element present
		if ($command eq "is_element_present") {if (! $Selenium->is_element_present(@parameters)){$SeleniumExecutionExit=1};last EXECUTIONS;}
		# Is location
		if ($command eq "is_location") {if (! $Selenium->is_location(@parameters)){$SeleniumExecutionExit=1};last EXECUTIONS;}
		# Is text present
		if ($command eq "is_text_present") {if (! $Selenium->is_text_present(@parameters)){$SeleniumExecutionExit=1};last EXECUTIONS;}
		# Is visible
		if ($command eq "is_visible") {if (! $Selenium->is_visible(@parameters)){$SeleniumExecutionExit=1};last EXECUTIONS;}
		# Open
		if ($command eq "open") {$Selenium->open(@parameters);last EXECUTIONS;}
		# Pause
		if ($command eq "pause") {$Selenium->pause(@parameters);last EXECUTIONS;}
		# Refresh
		if ($command eq "refresh") {$Selenium->refresh ();last EXECUTIONS;}
		# Select
		if ($command eq "select"){$Selenium->select(@parameters);last EXECUTIONS;}
		# Select window
		if ($command eq "select_window") {$Selenium->select_window(@parameters);last EXECUTIONS;}
		# Set timeout
		if ($command eq "set_timeout") {$Selenium->set_timeout(@parameters);last EXECUTIONS;}
		# Submit
		if ($command eq "submit") {$Selenium->submit(@parameters);last EXECUTIONS;}
		# Type
		if ($command eq "type") {$Selenium->type(@parameters);last EXECUTIONS;}
		# Type keys
		if ($command eq "type_keys") {$Selenium->type_keys(@parameters);last EXECUTIONS;}
		# Uncheck
		if ($command eq "uncheck") {$Selenium->uncheck(@parameters);last EXECUTIONS;}
		# Wait for page to load
		if ($command eq "wait_for_page_to_load") {$Selenium->wait_for_page_to_load(@parameters);last EXECUTIONS;}
		# Wait for element
		if ($command eq "wait_for_element_present") {$Selenium->wait_for_element_present(@parameters);last EXECUTIONS;}
		# Wait for text
		if ($command eq "wait_for_text_present"){$Selenium->wait_for_text_present(@parameters);last EXECUTIONS;}
		
		ErrorInfo ($currenttime,"ERROR: Command $command not recognised....");
	};

	return ($SeleniumText,$SeleniumCapture,$SeleniumExecutionExit,$SeleniumCookie);

}

sub ExecuteTask{
	my $SeleniumSession;
	foreach (@_){
		$SDomain="";
		LoggingInfo ($currenttime,"SELENIUM TASK --> $_");
		my ($command,@parameters)=split(/ /,$_);
		LoggingInfo ($currenttime,"SELENIUM EXECUTION --> command: [$command] [@parameters]");
		if ($SDomain eq "" && $command eq "open") {
			my $url = URI->new(@parameters);
			$SDomain = $url->scheme . '://' . $url->host;

			$SeleniumSession = WWW::Selenium->new(host => $SHost, 
							   port => $SPort,
							   browser => $SBrowser,
							   browser_url => $SDomain
							   );
			$SeleniumSession->start;
			$SeleniumSession->open(@parameters);
		}else{
			ExecuteTaskOneByOne($SeleniumSession,$command,@parameters);
		}
	}

}

sub ExecuteTaskPackage{
	my $tid = threads->tid();
	my @taskspackage=@_;
	#LoggingInfo ($currenttime,"SELENIUM PROCESS ID: [$tid]");
	my $count=1;
	foreach my $t (@taskspackage){
		print "[".$tid."/".$count."/".scalar(@taskspackage)."] Started TaskName: $t\n";
		LoggingInfo ($currenttime,"[".$tid."/".$count."/".scalar(@taskspackage)."] Executing TaskName: $t") if ($DEBUG ne 0);
		my $SeleniumSession;
		foreach (@{$tasks_in_file{$t}}){
			$SDomain="";
			LoggingInfo ($currenttime,"SELENIUM TASK --> $_");
			my ($command,@parameters)=split(/ /,$_);
			LoggingInfo ($currenttime,"SELENIUM EXECUTION --> command: [$command] [@parameters]");
			if ($SDomain eq "" && $command eq "open") {
				my $url = URI->new(@parameters);
				$SDomain = $url->scheme . '://' . $url->host;

				$SeleniumSession = WWW::Selenium->new(host => $SHost, 
								   port => $SPort,
								   browser => $SBrowser,
								   browser_url => $SDomain
								   );
				$SeleniumSession->start;
				$SeleniumSession->open(@parameters);
			}else{
				ExecuteTaskOneByOne($SeleniumSession,$command,@parameters);
			}
			
		}
		#Always close ...
		$SeleniumSession->close();
		$SeleniumSession->stop;
		print "[".$tid."/".$count."/".scalar(@taskspackage)."] Executed TaskName: $t\n";
		LoggingInfo ($currenttime,"[".$tid."/".$count."/".scalar(@taskspackage)."] Executed TaskName: $t") if ($DEBUG ne 0);
		$count++;
	}
	
}


sub TasksPackages{
	my ($nproc,@array) = @_;

	my @VAR = map { [] } 1..$nproc;
	my @idx = sort map { $_ % $nproc } 0..$#array;

	for my $i ( 0..$#array ){
			push (@{$VAR[ $idx[ $i ] ]}, $array[ $i ]);
	}
	return @VAR;
}
