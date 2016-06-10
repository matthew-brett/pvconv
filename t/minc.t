#!/usr/bin/perl -w	
# -*-perl-*-

use Test::More tests => 4;
use File::Compare;
use Data::Struct::Matfile;
use Math::Matrix;

$eg_dir     = "eg";
$out_dir    = "eg/minc";
$data_dir   = "BadBanana_01";
$ok_dir     = "BadBanana_ok";
@out_files = qw(BadBanana_01_18);
@out_exts = qw(mnc brkhdr);
  
$tmp = system("perl bin/pvconv.pl -outtype minc $eg_dir/$data_dir -verbose -outdir $out_dir");
is( $tmp, 0, 'pvconv.pl ran successfully' );

foreach $out_file(@out_files) {
    foreach $ext(@out_exts) {
	$out_fname = "$out_dir/$out_file.$ext";
	ok( (-e $out_fname), "$out_fname exists"); 
    }
}

$tmp = system('mincdiff -body eg/minc/BadBanana_01_18.mnc eg/BadBanana_ok/BadBanana_01_18.mnc');
is( $tmp, 0, 'Comparing image data with mincdiff' );


	
unlink <eg/minc/BadBanana*>;
