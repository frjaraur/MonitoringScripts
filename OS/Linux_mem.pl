#!/usr/bin/env perl
use strict;
use warnings;
my %mem;
open (MEMINFO,'</proc/meminfo');
while (<MEMINFO>){
	my ($var,$value)=split(' ',$_);
	$var=~s/://g;
	$mem{$var}=$value;
}

#foreach my $k (keys %mem){
#	print "$k --> $mem{$k}\n";
#}

my $percentused=100*($mem{'MemTotal'}-($mem{'MemFree'}+$mem{'Buffers'}+$mem{'Cached'}))/$mem{'MemTotal'};

printf ("%.1f \n",$percentused);