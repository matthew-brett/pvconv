# Bruker::Utils package; parsing for Bruker data format
#
# $Id: Utils.pm,v 1.2 2004/09/14 21:30:45 matthewbrett Exp $

package Bruker::Utils;

use Carp;
use File::Basename;
use Math::Matrix 0.4;
require Exporter;
@ISA = qw( Exporter );
@EXPORT = qw( );
@EXPORT_OK = qw(bruker_series bruker_find_dir parse_bruker_params 
		bruker2generic bruker_transposition bruker_text_headers);

use strict;
use vars qw($VERSION );

$VERSION = 0.17;

# Bruker text files to load, with error messages
my($subjfile) = [["subject"],
		 "no subject info - minor problem"];
my(@paramfiles) = (
		   [["%d/imnd", "%d/method"],
		    "input params - transformation matrix will fail"],
		   [["%d/acqp"],
		    "output params - expect problems with size, timing etc"],
		   [["%d/pdata/%d/reco"], 
		    "reco params - conversion will probably fail"],
		   [["%d/pdata/%d/d3proc"],
		    "image display params - used if other files are missing"],
		  );

# option defaults
my(%text_opt_defs) = (
		 'anon',  1,
		 );


sub bruker_series{
# gets series nos from Bruker directory
    my $pv_dir = shift;
    my(@flist, $f, @seriesnos);
    @flist = <${pv_dir}/[0-9]*>;
    foreach $f(@flist) {
	if (-d $f) {
	    $f =~ /.*?(\d+)$/;
	    @seriesnos = (@seriesnos, $1);
	}
    }
    return @seriesnos;
}    

sub bruker_find_dir{
# does check / find for Bruker directory
    my ($pv_start, $one_multf, $options, @rest) = @_;
    my @searchpath = @rest ? @rest : 
	defined($options->{dbpath}) ? @{$options->{dbpath}} : 
	    ();
    my ($pv_name, $pv_path, $pv_ext, $spath, 
	@flist, $s_ext, $s_targ, @dirlist);
    $pv_start =~ s/\/$//; # strip trailing path sep
    ($pv_name, $pv_path, $pv_ext) = fileparse($pv_start,'\..*');
    if ($pv_path eq './' && $pv_start !~ "^./") { # path not given
	# check each search directory, last first
	@searchpath = ('.', @searchpath);
    } else { 
	@searchpath = $pv_path;
    }
    @searchpath = reverse(@searchpath);

    # add asterisk for search
    $s_ext = $pv_ext eq "" ? "*" : $pv_ext;
  SEARCHLOOP: foreach $spath(@searchpath) {
      $s_targ = "$spath/$pv_name$s_ext";
      print "Searching for $s_targ...\n" if $options->{verbose};
      if ($pv_ext ne "") { # we know what we are looking for
	  if (-d $s_targ) {
	      push(@dirlist, $s_targ);
	      last SEARCHLOOP if $one_multf;
	  }
      } else { # use input as root file name
	@flist = ();
	foreach (glob($s_targ)) {
	  push(@flist, $_) if (-d);
	}
	if (@flist) {
	  @dirlist = (@dirlist, @flist);
	  last SEARCHLOOP if $one_multf;
	}
      }
    }
    return (\@dirlist, \@searchpath);
  }

# get header files info
sub bruker_text_headers{
    my($pv_dir, $seriesno, $recono, $in_opts) = @_;
    my(%options) = %text_opt_defs;
    foreach (keys(%$in_opts)) {
	$options{$_} = $in_opts->{$_};
    }

    my($pfile, $file_loc, $bhstr, $warning, $hdrdata, $ptry, $foundf);
    local $/;

# add subject info if required
    @paramfiles = ($subjfile, @paramfiles) if (!$options{anon});

# initialize file string
    $hdrdata = "";
    $warning = "";

# cycle through the files passed
    PFILE: foreach $pfile(@paramfiles) {
	$foundf = 0;
	PFILETRY: foreach $ptry(@{$pfile->[0]}) { 
	    # do variable substitution
	    $file_loc = sprintf($ptry, $seriesno, $recono);
	    $bhstr = $pv_dir . "/" . $file_loc;
	    if (open(TD,"<$bhstr") ) {
		$foundf = 1;
		last PFILETRY;
	    }
	}
	unless ($foundf) {
	  $warning .=  "No $file_loc file; $pfile->[1]; continuing...\n";
	  next PFILE;
	}

# Read input files as one long record.
	{
	    local $/;  
	    $hdrdata=$hdrdata . <TD>;
	}
	close TD;
    }

# dos2unix strip
    $hdrdata =~ s/\r//sg;

    return($hdrdata, $warning);
}

# Parse Bruker parameter file (passed as string) and return as hash
sub parse_bruker_params{
    my($hdrdata) = shift;

    my($i, $j, $k, $l, $record, $fname, $fval, @arr, @arels, %fields);

# strip out vis sections
    $hdrdata =~ s/(^\$\$ \@vis=(.|\n)*?)(^\#\#)/$3/mg;
 
# to records
    foreach $record (split(/\#\#/, $hdrdata)){
	($fname, $fval) = split(/=/,$record);
	if (defined($fname)) {
	    if ($fname =~ s/^\$// ) {
		chomp($fval);
		if ($fval ne "") {
		    if ($fval =~ s/\((.*)\)\n//) {
			@arels = split(/,/, $1);
			if ($fval =~ /^<(.*)>$/) {
			    $fields{$fname} = $1;
			}
			else {
			    # deals with 1D or 2D or 3D arrays
			    @arr = split(/\s+/, $fval);
			    if (@arels==3){ # 3D
				# fills rowwise - is this correct?
				$l=0;
				for ($i=0;$i<$arels[0];$i++){
				    for ($j=0;$j<$arels[1];$j++){
					for ($k=0;$k<$arels[2];$k++){
					    $fields{$fname}[$i][$j][$k]=$arr[$l];
					    $l++;
					}
				    }
				}
			    } elsif (@arels==2) { # 2D
				# fills rowwise - is this correct?
				$k=0;
				for ($i=0;$i<$arels[0];$i++){
				    for ($j=0;$j<$arels[1];$j++){
					$fields{$fname}[$i][$j]=$arr[$k];
					$k++;
				    }
				}
			    } else {
				$fields{$fname} = [@arr];
			    }
			}
		    } else {	# not an array
			$fields{$fname}=$fval;
		    }
		}
	    }
	}
    }
    return %fields;
}

# parses Bruker header into a generic format. When adding a format,
# why not add it here, in case your calculations are useful to the
# rest of us?  The Bruker header is a bit confusing.  Here's some
# terms to start.  Each time a subject gets into the scanner and gets
# scanned, is a 'session'.  Each individual scan, or time series, is a
# 'series'.  A series may be 3d (volume acquisition) or 2d (slice
# acquisition).  For each volume (3d) or slice (2d), there may be more
# than one scan acquired. For example, the T2/PD scans are two images
# (for each slice) acquired during the same scan (=series) I will term
# this as a 'layer', so that a normal strucutural has one 'layer',
# whereas the T2/PD scan has two layers.  These layers are combined in
# the reconstructed data file (i.e interleaved - volume by volume in
# the 3D case, and slice by slice in the 2D case).  The total number
# of images for one volume (slices * layers for 2D, layers for 3D), I
# will term the number of 'images' for that scan.  The reconstruction
# can output images with the read/phase or read/slice, phase/slices
# dimensions transposed (this transposition is _not_ reflected in the
# image dimensions from the RECO file, but it _is_ reflected in the
# dimensions in the d3proc file).  Each image can be differentially
# transposed.  See the paravision documents for more details, and some
# confusing parameter names.

# conversion between Bruker and other datatypes
my(%dataconv) = (
		 '_8BIT_UNSGN_INT', => {'bytes'   => 1,
					'd3no'    => 2, #?
					'min'     => 0,
					'max',    => 255,
					'anatype' => 2,
					'mnctype' =>  '-unsigned -byte'},
		 '_16BIT_SGN_INT' ,  => {'bytes'  => 2,
					 'd3no'    => 3,
					 'min'     => -(2**15),
					 'max',    => (2**15-1),
					 'anatype' => 4,
					 'mnctype' => '-signed -short'},
		 '_32BIT_SGN_INT' , => {'bytes'   => 4,
					'd3no'    => 5,
					'min'     => -(2**31),
					'max',    => (2**31-1),
					'anatype' => 8,
					'mnctype' => '-signed -long'}
		     );

# RECO transpose coding - see Image_Re.pdf
#1. If (RECO_transposition[i] = 0), no transposition is to be done.
#
#2. If (0 < RECO_transposition[i] < ACQ_dim), the two consecutive data
#directions given by RECO_transposition[i] and RECO_transposition[i] +
#1 will be transposed.
#
#3. If (RECO_transposition[i] = ACQ_dim), the first and final data
#directions will be transposed.
#
#Please note that for ACQ_dim = 2 the two values 1 and 2 are both legal
#for RECO_transposition[i] and will have the same effect; the first and
#second dimensions will be transposed.

sub bruker_transpose {
    my($bhdr, $layer) = @_;
    my $code = $bhdr->{'RECO_transposition'}[$layer];
    return [0, 0, 'none'] if ($code == 0); 
    my $is2d = ($bhdr->{ACQ_dim} == 2);
    return [0, 1, 'read/phase'] if ($is2d || $code == 1);
    return [1, 2, 'phase/slice'] if ($code == 2);
    return [0, 2, 'read/slice'];
}

# option defaults
my(%opt_defs) = (
		 'quiet',   1,
		 'verbose', 0,
		 'frecofix',1,
		 'layers',  1
		 );

sub bruker2generic{
    my ($bhdr, $inopts) = @_;
    my %options = %opt_defs;
    foreach (keys(%$inopts)) {
	$options{$_} = $inopts->{$_};
    }

    my $i4 =  Math::Matrix->eye(4);
    my $swaps = $i4->new([-1, 0, 0, 0],
			 [0, -1, 0, 0],
			 [0,  0, 1, 0],
			 [0,  0, 0, 1]);

    my ($key, $code, @t, $tmp, $bruk_trans, @acq_dim);
    my ($start, $ft2mm, $trans, $recoff, $so_far, $rotn, $vx2mm, $radio);
    my (@ftdim, $is2d, @fov, @vox, $vox, $off, $i, $j, $gradmat, @vector);

	
   
    my %ghdr = ();
    my $i1 = 0;

    # get the dimensionality of the acquisition
    $ghdr{dimensions} = @{$bhdr->{'RECO_size'}};
    if ($ghdr{dimensions} < 2) {
	unless ($options{quiet}) {
	    warn "Do not know how to handle data of less than two dimensions";
	}
    }

    # fill 2D or 3D worth of dimensions etc
    $ghdr{dim} = [@{$bhdr->{'RECO_size'}}];
    $ghdr{fov} = [@{$bhdr->{'RECO_fov'}}];
    
    # voxel dimensions in mm    
    foreach $i (0..($ghdr{dimensions}-1)) {
	$ghdr{vox}[$i] = $ghdr{fov}[$i] * 10 / $ghdr{dim}[$i];
    }

    # slice separation mode, see below
    $ghdr{sl_mode} = $bhdr->{'ACQ_slice_sepn_mode'};

    # test to see if we have an ACQP file
    if (defined($ghdr{sl_mode})) {
	# We have an ACQ file
	if ($ghdr{dimensions} < 3) { 
	    # This is a 2D image
	    # Therefore we still need slice information 
	    $ghdr{dim}[2] = $bhdr->{'NSLICES'};
	    $ghdr{sl_thick} = $bhdr->{'ACQ_slice_thick'};
	    $ghdr{vox}[2]=$bhdr->{'ACQ_slice_thick'};
	    # slices can be equidistant, contiguous, var parallel
	    # or var angle.  The slice separation as a single no
	    # only makes sense in the non Var case
	    if ((($ghdr{sl_mode} eq "Equidistant") ||
		 ($ghdr{sl_mode} eq "Contiguous"))
		&& defined($bhdr->{'ACQ_slice_sepn'})) {
		$ghdr{sl_sepn} = $bhdr->{'ACQ_slice_sepn'}[0];
		$ghdr{vox}[2] = $ghdr{sl_sepn} if ($ghdr{sl_sepn} > 0);
	    }
	} else {		# 3D
	    $ghdr{sl_thick}= $ghdr{vox}[2];
	    $ghdr{sl_sepn} = $ghdr{sl_thick};
	}
	$ghdr{sl_gap} = $ghdr{sl_sepn} > 0 ? 
	    $ghdr{sl_sepn} - $ghdr{sl_thick} : 0;

	# NI is the total number of images (=images) acquired in a
	# repetition so, for a 2D volume, and one layer (e.g. EPI),
	# this will be equal to the number of slices.  If there are
	# two layers, NI will be equal to the NSLICES *2. For a
	# 3D volume, NSLICES should I think be 1. 

	$ghdr{image_nr}= $bhdr->{'NI'}; 
	$ghdr{layer_nr} = $ghdr{image_nr} / $bhdr->{'NSLICES'};

	# no of volumes
	$ghdr{dim}[3]=best_of( $bhdr->{'ACQ_nr_completed'}, 1);

	# the TR.  This seems to be an array, with one element
	# for each multiplex step. We'll take the first I guess.
	$ghdr{vox}[3]=$bhdr->{'ACQ_repetition_time'}[0];

	# the slice acquisition order.  Well in fact the order of
	# acquisition of each 2D or 3D image, ie for a 2D scan, with two
	# layers and 10 slices, this array will have 20 elements

	$ghdr{objorder} = [@{$bhdr->{'ACQ_obj_order'}}];

    } else {

	# no ACQ, let's try our best, maybe using the d3proc file
	
	# guess no of layers

	$ghdr{layer_nr} = 1;
	
	# no of images (as for NI from acqp).  These could be different layers, 
	# could be slices, could be both, we don't know without the ACQP file

	$ghdr{image_nr}= @{$bhdr->{'RECO_transposition'}};

	if ($ghdr{dimensions} < 3) { 
        # we don't know how many slices, let's guess that the NI-like parameter
        # above actually refers to no of slices
	    $ghdr{dim}[2] = $ghdr{image_nr};
	}

	# maybe the total number of volumes can be calculated from the d3proc file
	if (!defined($bhdr->{IM_SIZ})) {
	    # we do seem to have a d3proc
	    # the following apparently overcomplex expression is to
	    # get round the situation where the dimensions have been 
	    # transposed, which will be reflected in the d3proc file
	    my($nslices)=$bhdr->{IM_SIX} * $bhdr->{IM_SIY}* $bhdr->{IM_SIZ} 
	    / $ghdr{dim}[0] / $ghdr{dim}[1] 
		* $bhdr->{IM_SIT};
	    $ghdr{dim}[3]=$nslices / $ghdr{dim}[2];
    	} else {
	    # we have to guess at no of volumes
	    $ghdr{dim}[3]=1;
	}
    }
    # set slice FOV if not already set
    if (!defined($ghdr{fov}[2])) {
	if (!defined($ghdr{vox}[2])) {
	    $ghdr{fov}[2] = 1; # no slice volume info
	} else {
	    $ghdr{fov}[2] = $ghdr{vox}[2] * $ghdr{dim}[2] / 10;
	}
    }

    # set use of layers from command line option
    if (!$options{layers}) {
	if ($ghdr{layer_nr} > 1) {
	    unless ($options{quiet}) {
		warn "Reset layer number to 1 from $ghdr{layer_nr}\n";
	    }
	    $ghdr{dim}[$ghdr{dimensions}] *= $ghdr{layer_nr};
	    $ghdr{layer_nr} = 1;
	}
	$ghdr{dim}[3] = $options{timelength};
    }

    # set no of time points from command line option
    if ($options{timelength}) {
	$ghdr{dim}[3] = $options{timelength};
    }

    # transposition.  For each image, and therefore for each slice
    # for a 2D experiment, the image can have its dimensions
    # transposed in the output reconstructed image.  This is dictated
    # by the REC0_transposition parameter, which has one value for
    # each layer for a 3D series, and one value for each layer for
    # each slice for a 2D series.  This transposition is not yet
    # reflected in the FOV and image dimensions we have recorded
    # above.  Calculate the transposed dimensions for each layer and store.
    # The paravision parameter is called RECO_transpose_dim in the docs, but not
    # in the actual reco files ? version change

    my($l, $r, $oimgno);    
    foreach $l (0..$ghdr{layer_nr}-1) {
	$ghdr{transpose}[$l]{code}=$bhdr->{'RECO_transposition'}[$l];
	for ($r=$l+$ghdr{layer_nr};$r<$ghdr{image_nr}-1;$r+=$ghdr{layer_nr}){
	    if ($bhdr->{'RECO_transposition'}[$r] && # maybe we have not enough tranposes
		($ghdr{transpose}[$l]{code}!=$bhdr->{'RECO_transposition'}[$r])) {
		unless ($options{quiet}) {
		    warn ("Different transpositions for the same image in ".
		     "the same volume: confusing, expect ugliness");
		}
	    }
	}

	# work out the transposed dimensions
	$ghdr{transpose}[$l]{dim} = [@{$ghdr{dim}}];
	$ghdr{transpose}[$l]{vox} = [@{$ghdr{vox}}];
	$ghdr{transpose}[$l]{fov} = [@{$ghdr{fov}}];

	$bruk_trans = bruker_transpose($bhdr, $l);

	# may need to transpose dimensions
	swapels(@{$bruk_trans}[0,1],$ghdr{transpose}[$l]{dim});
	swapels(@{$bruk_trans}[0,1],$ghdr{transpose}[$l]{vox});
	swapels(@{$bruk_trans}[0,1],$ghdr{transpose}[$l]{fov});
	$ghdr{transpose}[$l]{descrip} = $bruk_trans->[2];

	# now set the 4x4 transformation matrix
	
	# check that position parameters are defined
	# this code needs generalizing
	if (best_of(
		    $bhdr->{IMND_read_offset},
		    $bhdr->{PVM_ReadOffset}, 
		    $bhdr->{PVM_SPackArrReadOffset})
	    ) {

# Compile matrix
	    $is2d = (@{$bhdr->{ACQ_fov}} == 2);
	    $start = $i4->clone();

# transposition
	    $tmp = $start->[$bruk_trans->[0]];
	    $start->[$bruk_trans->[0]] = $start->[$bruk_trans->[1]];
	    $start->[$bruk_trans->[1]] = $tmp;
		
# reco offset
	    $recoff = $i4->clone();
	    $recoff->[0][3] =  $bhdr->{RECO_offset}[0][$l];
	    $recoff->[1][3] =  $bhdr->{RECO_offset}[1][$l];

	    if ($is2d) {
		$recoff->[2][3] = 0;
	    } else {
		$recoff->[2][3] =  $bhdr->{RECO_offset}[2][$l];
	    }

# ft voxels -> mm
	    $ft2mm = $i4->clone();
	    @ftdim = @{$bhdr->{RECO_ft_size}};
	    @acq_dim = @{$bhdr->{ACQ_fov}};
	    if ($is2d) {
		push(@ftdim, $bhdr->{NSLICES});
		push(@acq_dim, $ghdr{fov}[2]);
	    }
	    foreach $i(0..2) {
		$vox = $acq_dim[$i] / $ftdim[$i] * 10;
		$off =  ($ftdim[$i]+1)/2 * -$vox;
		$ft2mm->[$i][$i] = $vox;
		$ft2mm->[$i][3] = $off;
	    }

# translation offset in read/phase/slice
	    $trans = $i4->clone();
	    if (defined($bhdr->{IMND_read_offset})) {
		$trans->[0][3] = $bhdr->{IMND_read_offset}[0];
		$trans->[1][3] = best_of(
					 $bhdr->{IMND_phase1_offset}[0],
					 $bhdr->{ACQ_phase1_offset}[0],
					 0);
		$trans->[2][3] = $bhdr->{IMND_slice_offset};
	    } else {
		$trans->[0][3] = mean(@{
		    best_of($bhdr->{PVM_ReadOffset}, 
			   $bhdr->{PVM_SPackArrReadOffset})
		       });
		$trans->[1][3] = mean(@{
		    best_of($bhdr->{PVM_Phase1Offset}, 
			   $bhdr->{PVM_SPackArrPhase1Offset})
		       });
		$trans->[2][3] = mean(@{
		    best_of($bhdr->{PVM_SliceOffset}, 
			   $bhdr->{PVM_SPackArrSliceOffset})
		       });
	    }

# gradient matrix - is transposed
# There is one (3x3) gradient matrix for each slice - see Para_Cla.pdf in the Paravision documentation
# Quoting:
# ACQ_grad_matrix - is a three dimensional array of doubles to describe the
# orientation of the images to be measured.
#   · The fast dimension has three items to describe gradient vectors for the Gx/
#      Gy/Gz coordinate system. The gradient vectors should also describe a
#      unit sphere with a radius of 1.0.
#   · The medium dimension has also three items to describe the read-, phase-
#      and slice gradient.
#   · The slow dimension is used to describe all slices to be measured.
	    $rotn = $i4->clone();
	    $gradmat = $bhdr->{ACQ_grad_matrix}[0];
	    for $i(0..2){
		for $j(0..2){
		    $rotn->[$i][$j] = $gradmat->[$j][$i];
		}
	    }

# whole thing
	    $vx2mm =  $rotn * $trans * $swaps * $ft2mm * $recoff * $start;

# do report
	    if ($options{showmat}) { # very verbose
		$start->print("Tranposition\n");
		$so_far = mat_so_far("Reco offset",$recoff, $start);
		$so_far = mat_so_far("fft to mm",$ft2mm, $so_far);
		$so_far = mat_so_far("Swap xy",$swaps, $so_far);
		$so_far = mat_so_far("Translations",$trans, $so_far);
		$so_far = mat_so_far("Rotations",$rotn, $so_far);
	    }

# do radiological conversion if nec
	    if ($options{radio}) {
		$radio = $vx2mm->eye(4);
		$radio->[0][0] *= -1;
		$vx2mm = $radio * $vx2mm;
		if ($options{verbose}) {
		    print "Converting matrix to radiological orientation\n";
		}
	    }

# and into generic header
	    $ghdr{mat}[$l] = $vx2mm;

	} else { 
	    if ($options{verbose}) {
		print "Can't find the data for orientation matrix\n" 
		}
	}
    }

    # data type 
    my($datatype);
    if ($bhdr->{'RECO_wordtype'}){
	$datatype = $bhdr->{'RECO_wordtype'};
    } else {
	# try and get datatype from d3proc file
	if ($bhdr->{DATTYPE}) {
	    $datatype = $dataconv{$bhdr->{DATTYPE}}{d3no};
	}
    }
    $ghdr{datatype} = {%{$dataconv{$datatype}}};
    $ghdr{datatype}{name} = $datatype;

    # the size in bytes of the images (potentially) interleaved
    $ghdr{layersize} = 1;
    foreach $i (0..$ghdr{dimensions}-1) {
	$ghdr{layersize} *= $ghdr{dim}[$i];
    }
    $ghdr{layersize} *= $ghdr{datatype}{bytes};

    # endianness of reconstructed data
    $ghdr{"endian"} = ($bhdr->{RECO_byte_order} eq 'littleEndian') ?
	'le':'be';

    # there's an endian problem with FRECO reconstructions
    # They report littleEndian, when in fact they are bigEndian
    # So, if the raw data is bigEndian, and the reco data is littleEndian,
    # then assume this is a FRECO reconstruction, and fix
    if ($options{frecofix} && 
	($bhdr->{'BYTORDA'} =~ /big/) &&
	($ghdr{"endian"} eq "le")) {
	if (!$options{quiet}) {
	    print "Fixing FRECO endian -> bigEndian\n";
	}
	$ghdr{"endian"} = "be";
    }

    # some details
    if ($bhdr->{'ACQ_time'}){
	$bhdr->{'ACQ_time'} =~ /(..:..:..)\s*(\w*\s*\w*\s*\w*)/;
	$ghdr{time_of_scan} = $1;
	$ghdr{date_of_scan} = $2;
    }

    # image type
    $ghdr{iscomplex}=0;
    if ($bhdr->{RECO_image_type}) {
	$ghdr{image_type}=$bhdr->{RECO_image_type};
	$ghdr{image_type}=~s/_IMAGE//; 
	if ($ghdr{image_type}=~ /COMPLEX/) {
	    $ghdr{iscomplex}=1; 
	}
    }

    # entire data block max/min values 
    if ($bhdr->{RECO_maxima}) {
	$ghdr{blockmax} = $ghdr{datatype}{min};
	foreach $i (@{$bhdr->{RECO_maxima}}) {
	    $ghdr{blockmax} = $i if ($i > $ghdr{blockmax});
	}
    } 
    if ($bhdr->{RECO_minima}) {
	$ghdr{blockmin} = $ghdr{datatype}{max};
	foreach $i (@{$bhdr->{RECO_minima}}) {
	    $ghdr{blockmin} = $i if ($i < $ghdr{blockmin});
	}
    } 
    return %ghdr;
}

sub swapels {
    my($elno1, $elno2, $rarr) = @_;
    my($tmp) = $rarr->[$elno1];
    $rarr->[$elno1] = $rarr->[$elno2];
    $rarr->[$elno2] = $tmp;
}

sub mean {
    my($i, $s);
    $s = 0;
    foreach $i(@_) {
	$s += $i;
    }
    return ($s / @_);
}

sub best_of {
    my $a;
    A: while (@_) {
	$a = shift;
	last A if (defined($a));
    };
	return $a;
}

sub mat_so_far {
    my($label, $in, $sofar) = @_;
    $in->print("$label\n");
    $sofar = $in * $sofar;
    $sofar->print("Result so far\n");
    return $sofar;
}
1;
