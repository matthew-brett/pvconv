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
# $Id: brk2mat.pl,v 1.2 2004/04/27 06:15:19 matthewbrett Exp $

use File::Basename;
use Getopt::Long;
use Pod::Usage;
use Bruker::Utils qw( parse_bruker_params bruker2generic );
use Math::Matrix;
use Data::Struct::Matfile;
use strict;

# version
my ($version) = "0.02";

my ($n, $p, $e);
my ($hdrdata, $brkhdr, %bhdr, %ghdr, $mat, $outname);
my($l, $r, $oimgno);    
my $brkext = 'brkhdr';
my $matext = 'mat';
my @outnames;
my $k = 0;

my  $matfile = Data::Struct::Matfile->new();

my($me)  = fileparse($0, "");

my(@opt_table) =   (
		    "help|h",        # print help message and exit
		    "man|doc",       # print documentation and exit
		    "version",       # returns version no
		    );

# get options
my(%options) = ();
&GetOptions (\%options, @opt_table) || exit 1;

# version
if ($options{version}) {
    printf "%s - version %4.2f\n", $me, $version;
}

# help messages
pod2usage(-exitstatus => 0, -verbose => 2) if ($options{man});
pod2usage(-exitstatus => 0, -verbose => $options{verbose})
  if ($options{help});
pod2usage(0) if ($#ARGV < 0);

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

__END__

=head1 NAME

brk2mat.pl - makes .mat file from .brkhdr file and prints to console

=head1 SYNOPSIS

brk2mat.pl my_file.brkdhr

Options:

    -help          print help message and quit
    -man           full documentation and quit
    -version       returns version no

=head1 OPTIONS

=over 8

=item B<-help>

Print a long help message and exit.

=item B<-man>

Prints the manual page and exit.

=item B<-version>

Returns version no to the console.

=head1 DESCRIPTION

B<brk2mat.pl> displays and writes image orientation from .brkhdr file

=head1 AUTHOR

Matthew Brett E<lt>mailto://matthew@mrc-cbu.cam.ac.ukE<gt>

=head1 LICENSE

This program is free software, you can redistribute it and/or modify it
under the terms of the Artistic License distributed with Perl version
5.003 or (at your option) any later version. Please refer to the
Artistic License that came with your Perl distribution for more
details.

=cut

