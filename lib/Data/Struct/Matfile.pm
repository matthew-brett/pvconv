# Data::Struct::Matfile - implements structure for single matrix matlab 5.3 mat file.
# This is primarily for writing mat files with a single real double format matrix
# but will read mat files in 5.3 format, if the name and size of the matrix is known.
#
# See: http://www.mathworks.com/access/helpdesk/help/pdf_doc/matlab/matfile_format.pdf
# and: http://bul.eecs.umich.edu/~crowej/matdump.html
#
# Thanks to Andrew Janke for helpful perl and matlab pointers
# some via his website at http://www.cmr.uq.edu.au/~rotor
#
# $Id: Matfile.pm,v 1.1 2004/04/22 18:26:03 matthewbrett Exp $

package Data::Struct::Matfile;

use Data::Struct::Base;
use Carp;

@ISA = ('Data::Struct::Base');

use strict;

my %miv = ('INT8'=>1,
	   'UINT8'=>2,
	   'INT16',=>3,
	   'UINT16'=>4,
	   'INT32'=>5,
	   'UINT32'=>6,
	   'SINGLE'=>7,
	   'DOUBLE'=>9,
	   'INT64'=>12,
	   'UINT64'=>13,
	   'MATRIX'=>14);

my %mic = ('CELL'=>1,
	   'STRUCT'=>2,
	   'OBJECT',=>3,
	   'CHAR'=>4,
	   'SPARSE'=>5,
	   'DOUBLE'=>6,
	   'SINGLE'=>7,
	   'INT8'=>9,
	   'INT16'=>10,
	   'UINT16'=>11,
	   'INT32'=>12,
	   'UINT32'=>13);

my $MEND = Data::Struct::Base::machine_endian();
my $endind = ($MEND eq 'be') ? 'MI':'IM';

my @Matdef  = (
	       ["header_text",     'a124',"mat file created by perl"],
	       ["version",         's',   0x0100],
	       ["endian_indicator",'a2', $endind],

	       ["matrix_dt",       'L', $miv{MATRIX}],
	       ["matrix_nb",       'L', 176],
	       
	       ["arrf_dt",         'L', $miv{UINT32}],
	       ["arrf_nb",         'L', 8],
	       ['arrf_val',        'L',[$mic{DOUBLE},0]],

	       ["dim_dt",         'L', $miv{INT32}],
	       ["dim_nb",         'L', 2*4],
	       ['dim_val',        'L',[4,4]],

	       ["name_dt",         's', $miv{INT8}],
	       ["name_nb",         's', 1],
	       ['name_val',        'a4','M'],

	       ["real_dt",         'L', $miv{DOUBLE}],
	       ["real_nb",         'L', 128],
	       ['real_val',       'd',[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]]
	       );

# store array in object to get hash representation
my $As_header = Data::Struct::Base->new(\@Matdef);
my $As_hash = $As_header->structure_as_hash();

my %defsizes = ('arrf'=>16,
		'dim'=>16,
		'name'=>8,
		'realtag'=>8);

my $swaptest = sub {
    my $self = shift;
    my $eqMI = ($self->endian_indicator() eq 'MI');
    return ($MEND eq 'be') ? 1 - $eqMI : $eqMI;
};

# no of bytes for double value
my $DBLBYTES = 8;

# boundary byte no (has to align to byte block this size);
my $BYTEBOUND = 8;

# new accepts a 2d array and a name as arguments, and adapts
# the resulting structure to read/write with mat files
# Default (no args) is mat struct for SPM .mat file
sub new {
    my $that = shift;
    my $class = ref($that) || $that;
    my $thismat = \@Matdef;
    my %sizes;
    if (@_) {
	my $arr = shift;
	croak "Expecting 2d array as input arg" 
	    unless ref($arr);
	%sizes = %defsizes;
	
	# sizes 
	my $m = scalar(@{$arr});
	my $n = scalar(@{$arr->[0]});
	$thismat->[$As_hash->{dim_val}{row}][2] = [$m, $n];

	# matrix needs transposing for matlab to read
	my (@vector, $c, $r);
	for $c(0..$n-1) {
	    for $r(0..$m-1) {
		push @vector, $arr->[$r][$c];
	    }
	}
	$thismat->[ $As_hash->{real_val}{row}][2] = [@vector];
	$thismat->[ $As_hash->{real_nb}{row}][2] = $m * $n * $DBLBYTES;
    }
    if (@_) { # name as well
	my $name = shift;
	my $len = length($name);
	if ($len < 5) { # compressed format needed
	    $thismat->[$As_hash->{name_dt}{row}][1] = 's';
	    $thismat->[$As_hash->{name_nb}{row}][1] = 's';
	    $thismat->[$As_hash->{name_nb}{row}][1] = 's';
	    $thismat->[$As_hash->{name_val}{row}][1] = "a4";
	    $sizes{name} = 8;
	} else { # uncompressed
	    $thismat->[$As_hash->{name_dt}{row}][1] = 'L';
	    $thismat->[$As_hash->{name_nb}{row}][1] = 'L';
	    my $width = ($len % $BYTEBOUND) ? 
		(int($len/$BYTEBOUND)+1) * $BYTEBOUND : $len;
	    $thismat->[$As_hash->{name_val}{row}][1] = "a$width";
	    $sizes{name}= 8 + $width;
	}	    
	$thismat->[$As_hash->{name_nb}{row}][2] = $len;
	$thismat->[$As_hash->{name_val}{row}][2] = $name;
    }
    my ($key);
    my $size = $thismat->[$As_hash->{real_nb}{row}][2];
    foreach $key(keys(%sizes)) {
	$size+= $sizes{$key};
    }
    $thismat->[$As_hash->{matrix_nb}{row}][2] = $size;
    
    my $self = $class->SUPER::new($thismat, 
			  'verbose'=> 0, 
			  'extension' => 'mat',
			  'enforce_extension' => 1, 
			  'endian', {'default_in', 'native',
				     'default_out', 'native',
				     'try_unswap', 1,
				     'swaptest',$swaptest},
			  @_);
    bless $self, $class; 
    return $self;
}

# return matrix
sub matrix {
    my $self = shift;
    croak "matrix is read-only: try ->new() to change matrix" if (@_);
    my $arr = [];
    # need to reshape and transpose
    my ($m, $n) = $self->dim_val();
    my @vector = $self->real_val();
    my ($c, $r);
    for $c(0..$n-1) {
	for $r(0..$m-1) {
	    $arr->[$r][$c] = shift(@vector);
	}
    } 
    return $arr;
}

sub matrix_name {
    my $self = shift;
    croak "matrix name is read-only: try ->new() to change matrix name" 
	if (@_);
    return $self->name_val();
}
1;
