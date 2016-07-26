#!/usr/bin/perl -w	
# -*-perl-*-

use Test::More;
use File::Compare;
use Data::Struct::Matfile;
use Math::Matrix;
use File::Which;

$eg_dir     = "eg";
$out_dir    = "eg/minc";
$data_dir   = "BadBanana_01";
$ok_dir     = "BadBanana_ok";
@out_files = qw(BadBanana_01_18);
@out_exts = qw(mnc brkhdr);

if( ! defined(which('mincdiff')) ) {
    plan skip_all => 'minc-toolkit not installed';
} else {
    plan tests => 4;
}
  
$tmp = system("perl bin/pvconv.pl -outtype minc $eg_dir/$data_dir -verbose -outdir $out_dir");
is( $tmp, 0, 'pvconv.pl ran successfully' );

foreach $out_file(@out_files) {
    foreach $ext(@out_exts) {
	$out_fname = "$out_dir/$out_file.$ext";
	ok( (-e $out_fname), "$out_fname exists"); 
    }
}

$tmp = system("mincdiff -body $out_dir/BadBanana_01_18.mnc $eg_dir/$ok_dir/BadBanana_01_18.mnc");
is( $tmp, 0, 'Comparing image data with mincdiff' );


	
unlink <eg/minc/BadBanana*>;
