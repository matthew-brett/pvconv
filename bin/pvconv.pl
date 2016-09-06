#!/usr/bin/perl -w

eval 'exec /usr/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell
#
# pvconv.pl
#
# Converts pv data files in their directories (with reco and acqp) to
# analyze format, and should be portable for more formats
#
# See http://pvconv.sourceforge.net
# and pod documentation (below) for usage etc
# See CHANGES file for change log
#
# Released under the same licence as perl
#
# Matthew Brett - matthewb@berkeley.edu
# based on pv2mnc and ana2mnc (see http://www.cmr.uq.edu.au/~rotor/software/)
# by Andrew Janke - rotor@cmr.uq.edu.au, with thanks
#
# $Id: pvconv.pl,v 1.6 2004/11/10 19:08:40 matthewbrett Exp $

use File::Copy;
use File::Basename;
use FileHandle;
use Getopt::Long;
use Pod::Usage;

# these will need to be installed from CPAN
use Getopt::ArgvFile;
use Math::Matrix;

# these come with pvconv
use Data::Struct::Analyze;
use Data::Struct::Matfile;
use Bruker::Utils 0.17
  qw( bruker_series bruker_find_dir parse_bruker_params bruker2generic 
      bruker_text_headers);

use strict;
use vars qw($VERSION );

# version
$VERSION = 0.57;

# extension for Bruker header text file
my($brkhdrext) = ".brkhdr";

# extensions for files of different types
my(%ext_types) = ( 
	       'analyze'        => ['img', 'hdr'], 
	       'minc'           => ['mnc'],   
	       );

# Getopt::long option definitions
my(@opt_table) =   (
		    "help|h",        # print help message and exit
		    "man|doc",       # print documentation and exit
		    "verbose",       # more messages 
		    "quiet|q",       # no messages
		    "version",       # returns version no
		    "showmat!",      # show .mat file calculation
		    "clobber!",      # overwrite preexisting files
		    "series=i@",     # one or more series to convert
		    "recono=i",      # reconstruction no
		    "dbpath=s@",     # path(s) to search for PV data
		    "ptype=s%",      # protocol name->image name encoding
		    "reshape!",      # whether to reshape (MINC only so far)
		    "stepdir=s",     # directions of increase x, y, z
		    "rawfile=s",     # rawfile to use
		    "outtype=s",     # output type, analyze or minc
		    "outdir|d=s",    # directory to output files
		    "outfile=s",     # name of file to output (extension ignored)
		    "view!",         # show image after conversion (MINC only)
		    "frecofix!",     # fix reported byte ordering for FRECO 
		                     # (paravision 2.0) reconstruction
		    "timelength=i",  # No in time series 
		    "all!",          # Convert all series in the directory
		    "layers!",       # Use or suppress layer information 
                                     #(treat layers as slices)
		    "radio!",        # radiological orientation for mat file 
                                     # if set, neurological (Bruker default) 
                                     # if not, or with -noradio
		    "dirext!",       # adds PV directory ext to output names
		    "anon!",         # exclude subject info 
		    );

# Factory option defaults
my(%opt_defs) = (
		 'quiet',   0,
		 'verbose', 0,
		 'clobber', 0,
		 'reshape', 0,
		 'frecofix',0,
		 'view',    0,
		 'recono',  1,
		 'dimorder','zyx',
		 'stepdir','+++',
		 'outtype', 'analyze',
		 'all',     1,
		 'layers',  1,
		 'radio',   0,
		 'dirext',  0,
		 'anon', 1,
		 );

my($me)  = fileparse($0, "");

my($f, $seriesno, $hdrdata, $pfile, $bhstr, %bhdr, $sctype, $prot,
   $inpoutfile, $outpath, $outfile, $def_fname, $pv_path, $pv_ext,
   $testfile, $rawfile, $file_loc, @extlist, $ext, $fn, %ghdr, $i,
   @seriesnos, $ptry, $warning);

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
    printf "%s - version %4.2f\n", $me, $VERSION;
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
die "Multiple directories matching $pv_dir:\n" 
    . join("\n", @$dirlist) if (@$dirlist > 1);
$pv_dir = $dirlist->[0];

# make new default outfile name
($def_fname, $pv_path, $pv_ext) = fileparse($pv_dir,'\..*');
$pv_ext=~ s/\./_/;
$def_fname.= $pv_ext if ($options{dirext});

# Series numbers, all flag resolution
if (defined($options{series})) {
    # series specification silently overrides all flag
    @seriesnos = @{$options{series}};
} else { # all flag 
    @seriesnos= bruker_series($pv_dir);
}

# more than one experiment => disallow rawfile input and output names
if (@seriesnos > 1) {
    if (defined($options{outfile})) {
	die("$me: cannot use outfile name with more than one series");
    }
    if (defined($options{rawfile})) {
	die("$me: cannot use rawfile name with more than one series");
    }
}
 
# check file output type
if (!defined($ext_types{$options{outtype}})){
    die "$me: don't recognise output format $options{outtype}\n";
}

# the output file name
if (defined($options{outfile})){
    $inpoutfile = $options{outfile};
}

if (defined($ARGV[1])) {
    warn(<< "EOM");
Output directory as second input argument is deprecated, and may be removed
in future versions of $me; please use the -outdir option instead.
EOM
    if (defined($options{outdir})) {
	unless ($options{quiet}) {
	    warn(<<"EOM");
Using second argument $ARGV[1] for output directory instead of
option -outdir $options{outdir}
EOM
	}
    }
    $options{outdir} = $ARGV[1];
}

# resolve conflicting outpath and outfile 
if (defined($inpoutfile)) {
    ($inpoutfile, $outpath) = fileparse($inpoutfile,'\..*?');
    if (defined($outpath)) { 
	if (defined($options{outdir}) && 
		  ($outpath ne $options{outdir})) {
	    warn "Path from output file name ($outpath) overrides" . 
		" -outdir ($options{outdir})\n" unless ($options{quiet});
	}
    }
    $options{outdir} = $outpath;
}

# check output directory
if (!defined($options{outdir})) {
    $options{outdir} = ".";
} else {
    $options{outdir} =~ s/\/$//;
    if (!-d $options{outdir}){ 
	die "$me: Output directory $options{outdir} appears not to exist\n"; 
    }
}

SERIESLOOP: foreach $seriesno (@seriesnos){
    
    if (!defined($options{rawfile})) { 
	$rawfile  = "$pv_dir/$seriesno/pdata/$options{recono}/2dseq"; 
    } else {
	$rawfile = $options{rawfile};
    }
    
    if (!-e $rawfile){ 
	unless ($options{quiet}) {
	    warn "$me: $rawfile does not appear to exist, have the data been reconstructed?\n";
	}
	next;
    }

# Read text header data
    ($hdrdata, $warning) = bruker_text_headers($pv_dir, $seriesno,
					       $options{recono}, \%options);
    unless (!($warning) || $options{quiet}) {
	warn  $warning;
    }
    next SERIESLOOP unless ($hdrdata);
    
# Parse entire block into hash
    %bhdr = parse_bruker_params($hdrdata);

# set the root outfile name using suffix, regexp pairs
    if(!defined $inpoutfile) { 
	# name parser
	$sctype = "";
	if (defined($bhdr{'ACQ_protocol_name'})) {
	    foreach $prot(keys(%{$options{ptype}})) {
		if ($bhdr{'ACQ_protocol_name'} =~ 
		    /$options{ptype}->{$prot}/i) {
		    $sctype = '_' . $prot;
		    last;
		}
	    }
	}
	$outfile = sprintf("%s_%.2d%s",$def_fname,$seriesno,$sctype);
    } else {
	$outfile = $inpoutfile;
    }
    $outfile = $options{outdir} . '/' . $outfile;

# check for preexisting files

    @extlist = (@{$ext_types{$options{outtype}}}, $brkhdrext);
    if (!$options{clobber}) {
	foreach $ext(@extlist) {
	    $testfile = $outfile . $ext;
	    if (-e ($testfile)){ 
		unless ($options{quiet}) {
		    warn "$me: $testfile exists, -clobber to overwrite\n"; 
		}
		next SERIESLOOP;
	    }
	}
    }

# write bruker header file
    $fn = $outfile . $brkhdrext;
    unlink $fn;
    unless (open (FN,">$fn")) {
	unless ($options{quiet}) {
	    warn "Can't open $fn $!";
	}
    }
    print FN "$hdrdata";
    close FN;

# report
    if (!$options{quiet}) {
    	print "Converting:       $pv_dir:$seriesno:$options{recono}\n" .
	      "Output root name: $outfile\n";
    }

# parse Bruker parameters into a generic header
    %ghdr = bruker2generic(\%bhdr, \%options);

# and write output image
    if  ($options{outtype} eq 'analyze') {
	write_analyze_image(\%ghdr, \%bhdr, $rawfile, $outfile);
    } 
    elsif ($options{outtype} eq 'minc') {
	write_minc_image(\%ghdr, \%bhdr, $rawfile, $outfile);
    } else {
	die "Unrecognized output format $options{outtype}\n";
    }
}
exit 0;

########################################################################
# subroutines

sub write_analyze_image {
    my($ghdr, $bhdr, $rawfile, $outfile) = @_;

# create a template analyze header
    my $h = Data::Struct::Analyze->new();

# fill the analyze header
    if (defined($bhdr->{SUBJECT_name_string})) {
	$h->patient_id($bhdr->{SUBJECT_name_string}) };
    if (defined($bhdr->{ACQ_protocol_name})) {
	$h->descrip($bhdr->{ACQ_protocol_name}) };
    if (defined($ghdr->{time_of_scan})) {
	$h->exp_time($ghdr->{time_of_scan}) };
    if (defined($ghdr->{date_of_scan})) {
	$h->exp_date($ghdr->{date_of_scan}) };
    if (defined($ghdr->{image_type})) {
	$h->data_type($ghdr->{image_type}) };

# data types 
    $h->datatype($ghdr->{datatype}{anatype});
    $h->bitpix($ghdr->{datatype}{bytes}*8);
    
# initialize the output files
    my($k, $l, $thdr, $o, @outnames, @outhandles, $rimgs_per_vol, $data, 
       $i, $ln, $cn, $n_out_imgs, @hdr_layer, @mat_layer, @complex_suff, @layer_suff);

# set up names for different output images
    if ($ghdr->{iscomplex}) {
	@complex_suff   = ('_real', '_imag');
    } else {
	@complex_suff   = ('');
    }
    @layer_suff   = ('');
    if ($ghdr->{layer_nr} > 1) {
	foreach $ln(0..$ghdr->{layer_nr}-1) {
	    $layer_suff[$ln] = '_acq' . $ln;
	} 
    }
    $n_out_imgs = $ghdr->{layer_nr} * ($ghdr->{iscomplex}+1);

# Do the header transposition stuff for each layer
    foreach $ln (0..$ghdr->{layer_nr}-1) {
	# copy header for this layer - which may have different transposes
	$hdr_layer[$ln] = $h->clone();
	foreach $i (1..4) {
	    if ($ghdr->{transpose}[$ln]{dim}[$i-1]) {
		$hdr_layer[$ln]->dim([$i],$ghdr->{transpose}[$ln]{dim}[$i-1]);
	    }
	    if ($ghdr->{transpose}[$ln]{vox}[$i-1]) {
		$hdr_layer[$ln]->pixdim([$i],$ghdr->{transpose}[$ln]{vox}[$i-1]);
	    }
	}
	if ($ghdr->{transpose}[$ln]{code} && $options{verbose}) {
	    print "Transposed $ghdr->{transpose}[$ln]{descrip} for layer $ln\n";
	}

        # to mat file object
	$mat_layer[$ln] = Data::Struct::Matfile->new($ghdr->{mat}[$ln], 'M')
	    if defined($ghdr->{mat}[$ln]);
    }

# make hdr and mat info, open img files
    $k = 0;
    foreach $cn(0..$ghdr->{iscomplex}) {
	foreach $ln (0..$ghdr->{layer_nr}-1) {
	    $outnames[$k] = $outfile . $layer_suff[$ln] . $complex_suff[$cn];
	    $outhandles[$k] = new FileHandle;
	    open($outhandles[$k], "+>$outnames[$k].img") or 
		die "Error opening file: $outnames[$k].img";
	    binmode($outhandles[$k]);  # needed for DOS etc

	    # write header and mat files
	    $hdr_layer[$ln]->write_to($outnames[$k],$ghdr->{"endian"});
	    $mat_layer[$ln]->write_to($outnames[$k])
		if defined($ghdr->{mat}[$ln]);
	    $k+=1;
	} 
    }
    

    if ($n_out_imgs == 1) {
	# only one layer, not complex: simplest case
	# copy 2dseq as analyze image file
	copy($rawfile, $outfile . '.img');
    } else {
	# more than one layer / channel, and/or complex
	open(IMG, "<$rawfile") || die "Error opening file: $rawfile";
	binmode(IMG);

	$rimgs_per_vol = $ghdr->{dim}[3] * $ghdr->{image_nr} / $ghdr->{layer_nr};
	$k = 0;
	foreach (0..$ghdr->{iscomplex}) {
	    foreach (0..$rimgs_per_vol-1) {
		foreach $ln(0..$ghdr{layer_nr}-1) {
		    sysread(IMG, $data, $ghdr->{layersize});
		    syswrite($outhandles[$k+$ln],$data,$ghdr->{layersize});
		}
	    }
	    # move to next of (real, complex)
	    $k+=$ghdr{layer_nr};
	}
	close(IMG);
    }
    foreach $o (0..$n_out_imgs-1) {
	close($outhandles[$o]);
	if (!$options{quiet}) {
	    print "Written analyze image $outnames[$o].img\n";
	}
    }
    if (!$options{quiet}) { print "\n";}
}

# write MINC image.  This is slightly adapted code from
# Andrew Janke's pv2mnc
sub write_minc_image{
    my($ghdr, $bhdr, $rawfile, $outfile) = @_;

    my($range_args, $demographics, $quiet, $clobber);

# maybe these in a default generic header
    my $stddimord    = 'zyx';
    my $stddimordtxt = 'zspace,yspace,xspace';

    my ($xstep, $ystep, $zstep) = split(//, $options{stepdir}, 3);
    $outfile .= '.mnc';

    if (defined($ghdr->{blockmin}) && defined($ghdr->{blockmin})) {
	$range_args = "-range $ghdr->{blockmin} $ghdr->{blockmax}" .
	    " -real_range $ghdr->{blockmin} $ghdr->{blockmax}";
    } else {
	unless ($options{quiet}) {
	    warn  "$me: No calculated min/max values, attempting to compensate\n";
	}
	$range_args = "-scan_range";
    }

    if ($bhdr->{SUBJECT_name_string}) {
	$demographics =  "-sattribute \':patient_name=$bhdr->{SUBJECT_name_string}\' ".
	    "-sattribute \':patient_dob=$bhdr->{SUBJECT_dbirth}\' ".
	    "-sattribute \':patient_sex=$bhdr->{SUBJECT_sex}\' ".
            "-sattribute \':patient_doa=$bhdr->{SUBJECT_date}\' ".
	    "-sattribute \':patient_weight=$bhdr->{SUBJECT_weight}\' ";
    } else {
	unless ($options{quiet}) {
	    warn  "$me: No subject file, creating a no-namer\n";
	}
	$demographics = '';
    }

# dont know how to deal with many layers
    if ($ghdr->{layer_nr} > 1) {
	die "Whoops; more than one layer in this dataset\n";
    }

# lengths 
    my ($xlength, $ylength, $zlength, $tlength) = (@{$ghdr->{transpose}[0]{dim}});
    
# do special case for time-ordered data (swap zlength and tlength)
# (does this work?)
    if ($options{dimorder} eq "time"){
	my $tmp = $tlength;
	$tlength = $zlength;
	$zlength = $tmp;
    }

   if ($tlength == 1){
    $tlength = '';
   } else {
   my $timestep =  $ghdr->{transpose}[0]{vox}[3]/1000;
   $tlength = "-sattribute time:units=seconds -dattribute time:step=$timestep -dattribute time:start=0 " . $tlength;
   }


# calculate step sizes and start positions.
    $xstep .= $ghdr->{transpose}[0]{vox}[0];
    $ystep .= $ghdr->{transpose}[0]{vox}[1];
    $zstep .= $ghdr->{transpose}[0]{vox}[2];

    my $xstart = -($xlength/2) * $xstep;
    my $ystart = -($ylength/2) * $ystep;
    my $zstart = -($zlength/2) * $zstep;

    if (!$options{quiet}) {
	my($fov) = sprintf("%2.2f %2.2f %2.2f", @{$ghdr->{transpose}[0]{fov}});
	print "--------------------------------------------------------------------\n" .
	    "$xlength * $ylength * $zlength \t $ghdr->{sl_thick} mm + $ghdr->{sl_gap} mm gap\n" .
	    "$ghdr->{blockmin} - $ghdr->{blockmax}\t [$xstart][$ystart][$zstart]\n" .
	    "$fov cm FOV \t $xstep, $ystep, $zstep \n" .
	    "--------------------------------------------------------------------\n";
    }

    if ($options{quiet}) {
	$quiet = '-quiet';
    } else {
	$quiet = '';
    }
    if ($options{clobber}) {
	$clobber = '-clobber';
    } else {
	$clobber = '';
    }

    my $args = "rawtominc $clobber -mri ".
        $demographics .
	    " -$options{dimorder} $ghdr->{datatype}{mnctype} -ounsigned -oshort ".
	    $range_args .
	    " -xstep  $xstep  -ystep  $ystep  -zstep  $zstep".
	    " -xstart $xstart -ystart $ystart -zstart $zstart".
	    " $outfile  $tlength $zlength $ylength $xlength < $rawfile\n";

    if ($options{verbose}) { print "$args"; }
    system($args) == 0 or die;

# Do any reshaping if needed
    if ($options{reshape}){

	$args = "mincreshape $quiet $clobber ";
	if ($options{dimorder} ne $stddimord){
	    $args .= " -dimorder $stddimordtxt";
	}
	if ($xstep < 0 || $ystep < 0 || $zstep < 0){
	    $args .= " +direction -dimsize zspace=-1";
	}
	$args .= " $outfile $outfile.res\n";

	print "*** Reshaping $outfile\n";
	if ($options{verbose}) { print "$args"; }
	system($args) == 0 or die;
	system("mv $outfile.res $outfile\n") == 0 or die;
    }

    if ($options{view}){ system "register $outfile\n"; }
}

__END__

=head1 NAME

pvconv.pl - converts Bruker format data to other image formats

=head1 SYNOPSIS

pvconv.pl [@configfile] [options] paravision_data_dir [output_dir]

e.g.

If the Bruker data is stored in a directory "/brukerdata/mysession",
and you want to create analyze format files in the current directory, then:

pvconv.pl /brukerdata/mysession/ -verbose -all 

will convert all the series in the Bruker data directory.

See http://pvconv.sourceforge.net for more
information.

Options:

    -help          print help message and quit
    -man           full documentation and quit
    -verbose       more messages, more detailed help output
    -quiet         no messages during operation
    -version       returns version no
    -clobber       overwrite pre-existing files
    -all           convert all series in the directory [default]
    -series        one or more series to convert
    -dbpath        one or more directories to search for PV data
    -ptype         one or more file name <-> protocol name pairs
    -outtype       output type, "analyze" or "minc"
    -outdir        directory to output files
    -outfile       name of file to output (extension ignored)
    -radio         use radiological orientation for orientation output 
    -noradio       use neurological orientation for orientation output [default]
    -showmat       display verbose sequential listing of orientation data
    -dirext        adds PV directory ext to output names
    -frecofix      fix reported byte ordering for FRECO and other reconstructions
    -rawfile       specify rawfile (2dseq) to use
    -anon          do not save subject data into brkhdr files
    -noanon        save subject data into brkhdr files
    -timelength    specify no of volumes in time series 
    -layers        separate images according to layer information [default]
    -nolayers      do not separate images according to layer information 
    -recono        reconstruction no to convert
    -reshape       whether to reshape (MINC only so far)
    -stepdir       directions of increase x, y, z
    -view          show image after conversion (MINC only)

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
conversion. Adding -verbose to -help outputs more help.

=item B<-quiet>

Turn off any messages during conversion

=item B<-version>

Returns version no to the console.

=item B<-clobber>

Will overwrite preexisting files. If there B<are> preexisting files, and
you do not use -clobber, pvconv will exit with an error message. 

=item B<-all>

Convert all series in the directory. This is the default behaviour.

=item B<-series>

Specify series to convert, e.g.

pvconv.pl /brukerdata/mysession/ -series 1 -series 3 

will convert series 1 and 3 only.  Defaults to -all

=item B<-dbpath>

Specify one or more directories to search for PV data.  This can be
used to give default search paths in which to look for the specified
paravision subject data. e.g.

pvconv.pl mysession -dbpath /brukerdata -dbpath /another/dir

If (as here) the required directory does not contain a path component,
seachpath is used to search for a matching dataset. Paths specified
later are searched first: here, "/another/dir" will be searched
before "/brukerdata".

If (as here) the required directory ("mysession") does not contain an
extension, then the program will search for any directory matching
"<inputname>*" - here "mysession*".  This allows you to search for
data where you know only the first few characters of the directory
name.

=item B<-ptype>

One or more file suffix / protocol name pairs for clever file naming -
e.g:

pvconv.pl /brukerdata/mysession/ -ptype T3=tripilot -series 1

This -ptype string will cause pvconv to match the contents of the
Bruker ACQ_protocol_name field with the regular expression after the
equals sign (here the regexp is just the string "tripilot").  If
pvconv finds a match, it will append the first string in the pair
(here "T3") to the output file name, preceded by an underscore.  Here
the output might be:

    ./mysession_01_T3.img
    ./mysession_01_T3.hdr
    ./mysession_01_T3.mat

The protocol name is treated as a perl regular expression; for
example, you might specify "-ptype EPI=(epi|fmri)" if you wanted files
with either "epi" or "fmri" in the protocol_name field to have "EPI"
appended to the output file name.  The match is not case sensitive.

These file suffix / protocol name pairs are probably best stored in
configuration files.

=item B<-outtype>

Specify output type, currently one of "analyze" or "minc".  "analyze"
is the default.

=item B<-outdir>

Directory to output converted image files; e.g.

pvconv.pl /brukerdata/mysession/ -all -outdir /home/me/images

The default output directory is the current directory.

=item B<-outfile>

Root name of image files to output (extension ignored); e.g.

pvconv.pl /brukerdata/mysession/ -series 2 -outname image2

will create Analyze format output files:

 ./image2.img
 ./image2.hdr
 ./image2.mat

pvconv derives the default file name from the name of the Bruker data
directory, the series number, and any matches it finds of the protocol
name with preset strings identifying image types (see -ptype option).

=item B<-frecofix>

Fix reported byte ordering for FRECO reconstructions in paravision
2.0, and for some other reconstructions. If the reco file specifies
that the reconstructed data has a different endianness from the raw
(FID) data, then the reconstructed data is assumed to have the
endianness of the raw data. Try this flag if you get a snowstorm
effect in converted images without it.

=item B<-radio>

Set orientation calculations to return radiological orientation.

=item B<-noradio>

Set orientation calculations to return neuroogical orientation (the
pvconv and Bruker default).

=item B<-showmat>

Shows a verbose output of the orientation matrix as it is built step
by step from the Bruker parameters.

=item B<-dirext>

Adds Bruker directory extension to output names. Bruker data directories
usually have an extension that is unique for the particular day of
scanning.  pvconv usually omits this extension from the default output
filename; e.g.

pvconv.pl /brukerdata/mysession.fs1 -series 1 

may generate a file: ./mysession_01.img

The -dirext option causes the extension to be added to the filename; e.g. 

pvconv.pl /brukerdata/mysession.fs1 -series 1 -dirext

may generate a file: ./mysession_fs1_01.img

=item B<-anon>

Omit Bruker subject information from .brkhdr txt file.  Very useful if
real subject names etc are stored in this file.  use -noanon to keep
subject information in brkhdr file.

=item B<-rawfile>

Specify raw image file to use as image data instead of 2dseq: e.g.

pvconv.pl /brukerdata/mysession/ -all -rawdata mydata.img

=item B<-timelength>

Specify no of volumes in time series.  This is useful in cases where
the reco etc files have incorrect parameters, and you know the actual
no of volumes.

=item B<-layers>

Separate images according to layer information; for example, multiecho
sequences such as combined T1/PD acquisitions have images from the two
echos interleaved.  This option will cause pvconv to split the
interleaved slices into two images. Use -nolayers to disable this behaviour.

=item B<-recono>

Reconstruction number to convert.  Usually there is only one; use e.g.

pvconv.pl /brukerdata/mysession/ -series 4 -recono 2

to convert a second reconstruction for series 4.

=item B<-reshape>

Whether to reshape (MINC only so far)

=item B<-stepdir>

Directions of increase x, y, z (MINC only)

=item B<-view>

Show image after conversion (MINC only)

=back

=head1 CONFIGFILE

Options can be specified by configuration files in the same format as
for the command line, except options can be specified across many
lines, and comments can be interposed: e.g

pvconv.pl /brukerdata/mysession @myconfig

where "myconfig" is the following text file

 # data search path, in search order
 -dbpath /cbu/imagers/wbic_data

 # file name ending for protocol regexps
 -ptype SPGR=spgr
 -ptype anatomique=anatom
 -ptype T3=tripilot
 -ptype template=template
 -ptype PD-T2=pd-t2
 -ptype EPI=(epi|new90|new100)
 -ptype phasemap=phase

 # frecofix by default
 -frecofix

Configuration files are read in the following order: .pvconv.pl in the
directory of the pvconv.pl script; .pvconv.pl in your home directory;
.pvconv.pl in the current directory; and any configuration file passed
on the command line.  Options in files read later override those in
earlier files.  Options passed on the command line override options
passed in .pvconv.pl files, and any options specified earlier on the
the command line than the @configfile item.

=head1 DESCRIPTION

B<pvconv.pl> converts Bruker format MRI data to Analyze image
format. It may also convert Bruker data to MINC format.

The program is based on the converters by Andrew Janke (
http://www.cmr.uq.edu.au/~rotor/software/ ) Many thanks to him for the
original programs and helpful suggestions.

=head1 FEATURES

pvconv reads the text header files from the Bruker data format (
http://www.mrc-cbu.cam.ac.uk/Imaging/Common/brukerformat.html ), and uses the
values therein to fill a header information for Analyze format images
( http://www.mrc-cbu.cam.ac.uk/Imaging/Common/analyze_fmt.html ), and
possibly MINC files.

=over 4

=item *

pvconv will try and work out the orientation of the scan in terms of
the magnet isocentre, and create reorientation matrices.  For Analyze
format images, the orientation is stored in Matlab .mat format, of a
type that can be read by SPM software:
http://www.mrc-cbu.cam.ac.uk/Imaging/Common/spm_format.html. In this way,
scans will be automatically coregistered when you use SPM for your
analysis.

=item *

If two acquisitions have been collected in the same image (e.g. dual
echo sequences) it will (by default - see the -layers option) create
separate files for each.

=item *

A text file containing all the Bruker text file parameters is
automatically saved with the analyze image (as a .brkhdr file) for
further reference.

=item *

Converted files can be saved with semi-sensible file names; for
example, let us say that the original data came from a directory
"/brukerdata/mysession".  You have converted files from the fifth
series collected in that session; the protocol name stored in the
Bruker files was "EPI_FID". Somewhere (see Cconfiguration files) you
had specified the protocol name / file name link, using "-ptype
EPI=epi" or similar.  The output files would be:

 ./mysession_05_EPI.hdr        (Analyze header)
 ./mysession_05_EPI.img        (Analyze image data)
 ./mysession_05_EPI.mat        (SPM orientation)
 ./mysession_05_EPI.brkhdr     (Bruker parameter text file data)

=back

=head1 AUTHORS

Matthew Brett E<lt>mailto://matthewb@berkeley.eduE<gt>

Andrew Janke E<lt>rotor AT cmr.uq.edu DOT auE<gt>

=head1 LICENSE

This program is free software, you can redistribute it and/or modify it
under the terms of the Artistic License distributed with Perl version
5.003 or (at your option) any later version. Please refer to the
Artistic License that came with your Perl distribution for more
details.

=cut
