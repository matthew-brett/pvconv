#!/usr/local/bin/perl -w
#
# brk2mat.pl
# 
# Takes bruker header (.brkhdr) file as input, and outputs new matlab
# .mat file, with 4x4 transformation to take image
# coordinates in voxels to mm in terms of magnet isocentre
#
# Matthew Brett - 24/08/01 
#
# $Id: brk2mat.pl,v 1.1 2004/04/22 18:26:03 matthewbrett Exp $

use File::Basename;
use Bruker::Utils qw( parse_bruker_params bruker2generic );
use Math::Matrix;
use Data::Struct::Matfile;
use strict;

my ($n, $p, $e);
my ($hdrdata, $brkhdr, %bhdr, %ghdr, $mat, $outname);
my($l, $r, $oimgno);    
my $brkext = 'brkhdr';
my $matext = 'mat';
my @outnames;
my $k = 0;

my  $matfile = Data::Struct::Matfile->new();

HDRLOOP: foreach $brkhdr(@ARGV) {

# output filename
    ($n, $p, $e) = fileparse($brkhdr, "\.brkhdr");
    if (!defined($e)) {
	warn  "Input file $brkhdr does not have extension '$brkext'\n";
	next HDRLOOP;
    }
    $outname = $p . $n;

# Read input files as one long record.    
    if (! open(BH,"<$brkhdr") ) {
	warn  "Could not open file; $brkhdr - !$\n";
	next HDRLOOP;
    }
    undef $/;  
    $hdrdata  = <BH>;
    $/="\n";
    close BH;

# Parse
    %bhdr = parse_bruker_params($hdrdata);
    %ghdr = bruker2generic(\%bhdr);

# cycle over layers
    foreach $l (0..$ghdr{layer_nr}-1) {

# get matrix
	$mat = $ghdr{mat}[$l];

# to mat file object
	$matfile = $matfile->new($mat, 'M');

# sort out names for interleaved volumes
	$outnames[$k] = $outname;
	if ($ghdr{layer_nr} > 1) {
	    $outnames[$k] .= "_acq${l}";
	}
	if ($ghdr{iscomplex}) {
	    $outnames[$k] .= "_real";
	    $outnames[$k+1] .= "_imag";
	}
	foreach (0..$ghdr{iscomplex}) {
# print to console
	    print "M value for $outnames[$k]\n";
	    $mat->print();

# store in mat file
	    $matfile->write_to($outnames[$k]);
	    $k+=1;
	} 
    }
}
