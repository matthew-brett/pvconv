#!/usr/bin/perl -w	
# -*-perl-*-

use Test::More tests => 3;

$tmp = system('perl bin/pvconv.pl eg/sample.001 -verbose -outdir eg');
is( $tmp, 0, 'pvconv.pl ran successfully' );
$tmp = system('perl bin/pvshow.pl eg/sample.001');
is( $tmp, 0, 'pvshow.pl ran successfully' );
$tmp = system('perl bin/brk2mat.pl eg/sample_02.brkhdr');
is( $tmp, 0, 'brk2mat.pl ran successfully' );
unlink <eg/sample_*>;
