#!/usr/local/bin/perl -w
#
# pvshow.pl
#
# Shows parameters from pv data files in their directories 
#
# Matthew Brett - matthewb@berkeley.edu
#
# $Id: pvshow.pl,v 1.1 2004/04/22 18:26:03 matthewbrett Exp $

use File::Basename;
use FileHandle;
use Getopt::Long;
use Pod::Usage;

# these need to be installed from CPAN
use Getopt::ArgvFile;
use Math::Matrix;

use Bruker::Utils 0.16
  qw( bruker_series bruker_find_dir parse_bruker_params bruker2generic 
      bruker_text_headers);

use strict;

# version
my ($version) = "0.02";

# extension for Bruker header text file
my($brkhdrext) = ".brkhdr";

my(@opt_table) =   (
		    "help|h",        # print help message and exit
		    "man|doc",       # print documentation and exit
		    "verbose",       # more messages 
		    "version",       # returns version no
		    "quiet",         # no messages
		    "series=i@",     # one or more series to convert
		    "recono=i",      # reconstruction no
		    "all",           # Show all series in the directory
		    "dbpath=s@",     # path(s) to search for PV data
		    );

# option defaults
my(%opt_defs) = (
		 'quiet',   1,
		 'verbose', 0,
		 'recono',  1,
		 'all',     1,
		 );

my($me)  = fileparse($0, "");

my($f, $seriesno, $hdrdata, $warning, $sctype, $prot, 
   $inpoutfile, $outpath, $outfile, $testfile, $rawfile, $file_loc,
   @extlist, $ext, $fn, %ghdr, $i, @seriesnos, $recodata, %bhdr); 

# deal with option files
&Getopt::ArgvFile::argvFile(
			    default=> 1,
			    home=> 1,
			    current=> 1,
			    );

# get options
my(%options) = ();
&GetOptions (\%options, @opt_table) || exit 1;

# version
if ($options{version}) {
    printf "%s - version %4.2f\n", $me, $version;
}

# fill undefined options with defaults
my $key;
foreach $key(keys(%opt_defs)) {
    if (!defined($options{$key})) {
	$options{$key}=$opt_defs{$key};
    }
}
$options{quiet} = 0 if $options{verbose};

# help messages
pod2usage(-exitstatus => 0, -verbose => 2) if ($options{man});
pod2usage(-exitstatus => 0, -verbose => $options{verbose})
  if ($options{help});
pod2usage(0) if ($#ARGV < 0);

# check data directory
my $pv_dir = $ARGV[0]; 
my ($dirlist, $searchpath) = bruker_find_dir($pv_dir, 1, \%options);
die "Found no matching data on searchpath: " 
    . join(", ", @$searchpath) . "\n" unless (@$dirlist);

STUDYLOOP: foreach $pv_dir(@$dirlist) {

# Series numbers, all flag resolution
    if (defined($options{series})) {
	# series specification silently overrides all flag
	@seriesnos = @{$options{series}};
    } else { # all flag 
	@seriesnos= bruker_series($pv_dir);
    }
    
  SERIESLOOP: foreach $seriesno (@seriesnos) {
# read in files, with errors as appropriate
      ($hdrdata, $warning) = bruker_text_headers($pv_dir, $seriesno,
						 $options{recono});
      unless (!($warning) || $options{quiet}) {
	  warn  $warning;
      }
      
# Parse entire block into hash
      %bhdr = parse_bruker_params($hdrdata);
      
# parse Bruker parameters into a generic header
      %ghdr = bruker2generic(\%bhdr, \%options);
      
# check for reconstructed data
      if (-e "$pv_dir/$seriesno/pdata/$options{recono}/2dseq") {
	  $recodata = "Yes";
      } else {
	  $recodata = "No";
      }
      
      # report
      print(sprintf("%s:%d: %s; time: %s; reps: %d; reco: %s\n", 
		    $pv_dir,
		    $seriesno,
		    $bhdr{ACQ_protocol_name}, 
		    $bhdr{ACQ_time},
		    $ghdr{dim}[3],
		    $recodata,
		    )
	    );
  }
}


########################################################################
# subroutines

__END__

=head1 NAME

pvshow.pl - shows summary information for Bruker data

=head1 SYNOPSIS

pvshow.pl [@configfile] [options] paravision_data_dir 

e.g.

If the Bruker data is stored in a directory "/brukerdata/mysession":

pvshow.pl /brukerdata/mysession/ -verbose -all 

will display various bits of information for all the series in the
Bruker data directory.

Options:

    -help          print help message and quit
    -man           full documentation and quit
    -verbose       more messages, more detailed help output
    -quiet         no messages during operation
    -version       returns version no
    -all           display parameters for all series in the directory [default]
    -series        one or more series to display parameters for
    -dbpath        one or more directories to search for PV data

    @configfile 

    Configuration file containing any of the options above in format
    given by Getopts::Argvfile (www.cpan.org) - the format is
    the same as for the command line, but allowing multiple
    lines and comments.

=head1 OPTIONS

=over 8

=item B<-help>

Print a long help message and exit.

=item B<-man>

Prints the manual page and exit.

=item B<-verbose>

Gives out moderately helpful warning and other messages during image
parameter display. Adding -verbose to -help outputs more help.

=item B<-quiet>

Turn off any messages during parameter display

=item B<-version>

Returns version no to the console.

=item B<-all>

Display Parameters For all series in the directory. This is the default behaviour.

=item B<-series>

Specify series to display parameters for, e.g.

pvshow.pl /brukerdata/mysession/ -series 1 -series 3 

will display parameters for series 1 and 3 only.  Defaults to -all

=item B<-dbpath>

Specify one or more directories to search for PV data.  This can be
used to give default search paths in which to look for the specified
paravision subject data. e.g.

pvshow.pl mysession -dbpath /brukerdata -dbpath /another/dir

If (as here) the required directory does not contain a path component,
seachpath is used to search for a matching dataset. Paths specified
later are searched first: here, "/another/dir" will be searched
before "/brukerdata".

If (as here) the required directory ("mysession") does not contain an
extension, then the program will search for any directory matching
"<inputname>*" - here "mysession*".  This allows you to search for
data where you know only the first few characters of the directory
name.

=item B<-recono>

Reconstruction number to display parameters for.  Usually there is
only one; use e.g.

pvshow.pl /brukerdata/mysession/ -series 4 -recono 2

to display parameters for a second reconstruction for series 4.

=back

=head1 CONFIGFILE

Options can be specified by configuration files in the same format as
for the command line, except options can be specified across many
lines, and comments can be interposed: e.g

pvshow.pl /brukerdata/mysession @myconfig

where "myconfig" is the following text file

 # data search path, in search order
 -dbpath /cbu/imagers/wbic_data

Configuration files are read in the following order: .pvshow.pl in the
directory of the pvshow.pl script; .pvshow.pl in your home directory;
.pvshow.pl in the current directory; and any configuration file passed
on the command line.  Options in files read later override those in
earlier files.  Options passed on the command line override options
passed in .pvshow.pl files, and any options specified earlier on the
the command line than the @configfile item.

=head1 DESCRIPTION

B<pvshow.pl> displays parameters for Bruker format MRI data.

=head1 AUTHOR

Matthew Brett E<lt>mailto://matthew@mrc-cbu.cam.ac.ukE<gt>

=head1 LICENSE

This program is free software, you can redistribute it and/or modify it
under the terms of the Artistic License distributed with Perl version
5.003 or (at your option) any later version. Please refer to the
Artistic License that came with your Perl distribution for more
details.

=cut


