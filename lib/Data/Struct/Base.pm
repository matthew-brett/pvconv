# Data::Struct::Base - generic type for fixed-format binary data
#
# $Id: Base.pm,v 1.1 2004/04/22 18:26:03 matthewbrett Exp $

package Data::Struct::Base;

use Carp;
use File::Basename;
use vars qw($AUTOLOAD); 
use POSIX qw(:float_h :limits_h);
use strict;

# details for format specifiers - system specific
# The byte lengths of datatypes are assumed
my %Formspec = ('a'=> {'name','space padded string',
		       'type'=>'string',
		       'bytes'=> 1},
		'A'=> {'name','zero padded string',
		       'type'=>'string',
		       'bytes'=> 1},
		'c'=> {'name','signed char',
		      'type'=>'number',
		      'bytes'=> 1,
		      'min' => CHAR_MIN,
		      'max' => CHAR_MAX},
		'C'=> {'name','unsigned char',
		      'type'=>'number',
		      'bytes'=> 1,
		      'min' => 0,
		      'max' => UCHAR_MAX},
		's'=> {'name','signed short integer',
		       'type'=>'number',
		      'bytes'=> 2,
		      'min' => SHRT_MIN,
		      'max' => SHRT_MAX},
		'l'=> {'name','signed long integer',
		       'type'=>'number',
		      'bytes'=> 4,
		      'min' => LONG_MIN,
		      'max' => LONG_MAX},
		'L'=> {'name','unsigned long integer',
		       'type'=>'number',
		       'bytes'=> 4,
		       'min' => 0,
		       'max' => ULONG_MAX},
	       'f'=> {'name','float',
		       'type'=>'number',
		      'bytes'=> 4,
		      'min' => -(FLT_MAX),
		      'max' => FLT_MAX},
	       'd'=> {'name','double',
		       'type'=>'number',
		      'bytes'=> 8,
		      'min' => -(DBL_MAX),
		      'max' => DBL_MAX}
		);

my %INPFIELDS = ('fields_as_methods',1,
		 'verbose',1,
		 'extension',undef,
		 'enforce_extension',0
		 );

my %HASHFIELDS = ('endian', {'default_in'=> &machine_endian(),
			     'default_out'=> undef,
			     'lastinput' => undef,
			     'try_unswap' => 0,
			     'swaptest',undef}
		  );

my %OTHERFIELDS = ('_formspec',\%Formspec,
		   '_bindata',undef,
		   'binlen',undef,
		   'filename',undef,
		   'starr',undef,
		   'stash',undef);

# index of name, format and data rows
my ($NROW,$FROW,$DROW) = (0..2);

sub new {
    my ($class, $self, $arrref, $hf);
    my $that = shift;
    if (ref($that)) { # object call -> copy object
	$class = ref($that);
	if (@_ && ref($_[0])) {
	    $arrref = shift;
	} else {
	    $arrref = $that->{starr};
	}
	$self = {%$that};
	foreach $hf(keys(%HASHFIELDS)) {
	    $self->{$hf} = {%{$self->{$hf}}};
	}
    } else { # class call -> default object
 	$class  = $that;
	croak "Need format array for new class $class" unless (@_);
	$self = {%INPFIELDS, %OTHERFIELDS};
	foreach $hf(keys(%HASHFIELDS)) {
	    $self->{$hf} = {%{$HASHFIELDS{$hf}}};
	}
	$arrref = shift;
    }

    # fill fields from command line
    my %params = @_;
    my $name;
    foreach $name(keys(%params)) {
	if (exists($INPFIELDS{$name})) {
	    $self->{$name} = $params{$name};
	} elsif (exists($HASHFIELDS{$name})) { 
	    croak "Need hash as input for $name field" 
		unless (ref($params{$name}) eq "HASH");
	    # merge hashes
	    foreach $hf(keys(%{$params{$name}})) {
		$self->{$name}{$hf} = $params{$name}{$hf};
	    }
	} else {
	    croak "No '$name' field in class $class";
	};
    }

    # create hash etc from array, and copy array
    bless $self, $class;
    $self->init($arrref);
    return $self;
}

# parse and fill struct-ashash etc from struct->formatted
sub init {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need array ref for init function" unless (@_);
    my $arrref = shift;
    
    $self->{binlen} = 0;
    $self->{starr} = [];
    my ($row, @arr, $names, $name, @nicks, $fstr, $format, $width);
    my ($val, $numels, @names, $n);
    foreach $row (0..(@$arrref-1)) {
	@arr = @{$arrref->[$row]}[$NROW,$FROW,$DROW];
	($name, $fstr, $val) = @arr;

	# check for nicknames, copy if necessary
	if (ref($name)) {
	    $arr[$NROW] = [@$name];
	    @names = @$name;
	    ($name, @nicks) = @$name;
	} else {
	    @names = ($name);
	    @nicks = ();
	}

	# check field names do not clash with object methods
	if ($self->{fields_as_methods}) {
	    foreach $n(@names) {
		croak "Struct name clashed with object method $n" 
		    if ($self->can($n));
	    }
	}

	# parse and check format field
	($format, $width) = ($fstr =~ /(\D*)(\d*)/);
	croak "No format from $fstr" if $format eq "";
	croak "Unknown format $format" unless 
	    exists($self->{_formspec}->{$format});
	if ($self->{_formspec}->{$format}->{type} eq "string") {
	    $width = 1 if ($width eq "");
	} else {
	    $width = $self->{_formspec}->{$format}{bytes};
	    $fstr = $format;
	}

	# no of elements for array
	if (ref($val) eq 'ARRAY') {
	    $arr[$DROW] = [@$val];
	    $numels = scalar(@$val);
	} else {
	    $numels = 1;
	}

	# fill hash
	$self->{stash}{$name} = {'format' => $format,
				 'formstr' => $fstr,
				 'width'  => $width,
				 'doswap' => 
				     ($self->{_formspec}->{$format}{bytes} > 1),
				 'numels' => $numels,
				 'row'    => $row,
			     };
	
	# fill array copy
	@{$self->{starr}->[$row]}[$NROW,$FROW,$DROW] = @arr;

	# calculate length
	$self->{binlen} += $numels * $width;

	# add any nicknames
	foreach $n(@nicks) {
	    $self->{stash}{$n} = $self->{stash}{$name};
	}
    }
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or croak "$self is not an object";
    my $name = $AUTOLOAD;
    $name =~ s/.*://; # strip fully-qualified portion
    if ($self->{fields_as_methods} &&  
	exists $self->{stash}->{$name}) {
	# allowed field in struct
	return ($self->field($name, @_));
    }
}

# sets and / or returns value from struct, checking inputs
sub field {
    my ($arg, @outinds, @inpvals, @outvals, $i, $ind);
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need field name for field function" unless (@_);
    my $name = shift;
    croak "Do not recognize field name $name" unless 
	exists($self->{stash}->{$name});
    my $field = $self->{stash}->{$name};
    if ($field->{numels} == 1) { # scalar target
	if (@_) {
	    $arg = shift;
	    croak "Too many inputs to $name" if (@_);
	    $self->{starr}->[$field->{row}][$DROW] = 
		$self->_goodarg($field, $arg);
	}
	return $self->{starr}->[$field->{row}][$DROW];
    } else { # array target
	# no args, return whole array
	if (!@_) {
	    return @{$self->{starr}->[$field->{row}][$DROW]};
	}
	# one or more args - output array
	# if the first is a ref, we could have input vals
	if (ref($_[0])) {
	    @outinds = @{+shift};
	    if (@_) { # parse input values
		$arg = shift;
		if (ref($arg)) { # ref for input vals
		    croak "Unexpected extra inputs to array" if (@_); 
		    @inpvals =  @$arg;
		} else {
		    # not a ref, must be values
		    @inpvals = ($arg, @_);
		}
		croak "Different no of inputs and outputs for array" 
		    if (@inpvals != @outinds); 
	    }
	} else { # non ref first arg - array of indices
	    @outinds = @_;
	}
	@outvals = ();
	foreach $i(0..@outinds-1){
	    $ind = $outinds[$i];
	    croak "Index $ind out of range" 
		if ($ind < 0 || $ind >= $field->{numels});
	    if (defined($inpvals[$i])) { #assignment
		$self->{starr}->[$field->{row}][$DROW][$ind] = 
		    $self->_goodarg($field, $inpvals[$i]);
	    }
	    push(@outvals, $self->{starr}->[$field->{row}][$DROW][$ind]);
	}
	return (@outinds > 1) ? @outvals : $outvals[0];
    }
}

# checks format of scalar argument for field
sub _goodarg {
    my ($self, $field, $arg) = @_;
    croak "Arg needs to be scalar\n" if (ref($arg));
    my %fspec = %{$self->{_formspec}->{$field->{'format'}}};
    if ($fspec{type} eq 'number') {
	{
	    local $^W = 0;
	    croak "Arg $arg is not a number" if ($arg==0 && $arg ne "0");
	}
	croak "Number $arg too big for $fspec{name}" 
	    if ($arg > $fspec{max});
	croak "Number $arg too small for $fspec{name}" 
	    if ($arg < $fspec{min});
    } else { # string
	if (length($arg) > $field->{width}) {
	    my $oldarg = $arg;
	    $arg = substr($arg, 0,  $field->{width});
	    carp "Truncating $oldarg to $arg" if ($self->verbose());
	}
    }
    return $arg;
}

# fill from binary data
sub binary_in {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need binary input data" unless (@_);
    $self->{_bindata} = shift;
    my $swf = $self->_get_swf('in', @_);
    $self->_parsebin($swf);
    if ($self->endian('try_unswap') && &{$self->endian('swaptest')}($self)) {
	$swf = 1-$swf;
	$self->_parsebin($swf);
    }
    $self->{endian}{lastinput} = machine_endian($swf);
}

# parse the data 
sub _parsebin {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "No binary data to parse" unless defined($self->{_bindata});
    croak "Need swap flag" unless (@_);
    my $swf = shift;
    my($row, $buf, $n, $name, $val, @arr, $field);
    my $offset = 0;
    foreach $row (0..(@{$self->{starr}} -1 )) {
	@arr = @{$self->{starr}->[$row]}[$NROW,$DROW];
	($name, $val) = @arr;
	if (ref($name)) { $name = $name->[0]};
	$field  = $self->{stash}->{$name};
	foreach $n (0..($field->{numels}-1)) {
	    $buf = substr($self->{_bindata},$offset,$field->{width}); 
	    if ( $field->{doswap} && $swf ) {
		$buf = reverse($buf);
	    }
	    $val = unpack($field->{formstr}, $buf);
	    if ($field->{numels} == 1) {
		$self->{starr}->[$field->{row}][$DROW] = $val;
	    } else {
		$self->{starr}->[$field->{row}][$DROW][$n] = $val;
	    }		
	    $offset += $field->{width};
	}
    }
}

sub binary_out {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    my $swf = $self->_get_swf('out', @_);
    
# parse the data 
    my($row, $buf, $n, $name, $val, @arr, $field);
    $self->{_bindata} = "";
    foreach $row (0..(@{$self->{starr}} -1 )) {
	@arr = @{$self->{starr}->[$row]}[$NROW,$DROW];
	($name, $val) = @arr;
	if (ref($name)) { $name = $name->[0]};
	$field  = $self->{stash}->{$name};
	if (!ref($val)) { $val = [$val] };
	foreach $n (0..$field->{numels}-1) {
	    $buf = pack($field->{formstr},$val->[$n]);
	    if ( $field->{doswap} & $swf ) {
		$buf = reverse($buf);
	    }
	    $self->{_bindata} .= $buf;
	}
    }
    return  $self->{_bindata};
}

sub _get_swf {
    my $code;
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need in / out specifier" unless (@_);
    my $inout = shift;
    my $mend = machine_endian();    
    if (@_) {
	$code = shift;
    } else {
	$code = ($inout eq 'in') 
	    ? $self->endian('default_in') : $self->endian('default_out');
	unless (defined($code)) {
	    $code = $self->endian('lastinput');
	    $code = $mend unless defined($code);
	}
    }
    if ($code eq 'le') {
	return ($mend eq 'le') ? 0:1;
    } elsif ($code eq 'be') {
	return ($mend eq 'be') ? 0:1;
    } elsif ($code eq 'swap') {
	return 1;
    } elsif ($code eq 'native') {
	return 0;
    } else {
	croak "Unrecognized endian option $code";
    }
}
   
# tiny endian test, with swap as requested
sub machine_endian {
    if (scalar(@_) && ref($_[0])) {
	# called as method - discard object
	shift;
    }
    my $swf = (@_) ? shift : 0;
    my $end = (unpack("s", "AB") == 16706) ? 'le':'be';
    return ($swf) ? $end : ($end eq 'le') ? 'be':'le';
}

# prints out fields derived from structure
# in the order defined by the structure array
sub dump {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    my @fields;
    if (@_) { @fields = @_ } else { @fields = $self->struct_fields(); }
    my ($row, $name, $val);
    foreach $name (@fields) {
	if (defined($self->{stash}{$name})) {
	    $row = $self->{stash}{$name}{row};
	    $val = $self->{starr}->[$row][$DROW];
	    if (ref($val)) {
		$val = join(' ', @$val);
	    }
	    print "$name: $val\n";
	} else {
	    print "Field $name is not defined for this object\n";
	}
    }
}

sub struct_fields {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    my @fields = ();
    my ($row, $name, $val);
    foreach $row (0..(@{$self->{starr}} -1 )) {
	$name = $self->{starr}->[$row][$NROW];
	if (ref($name)) {
	    push(@fields, @$name);
	} else {
	    push(@fields, $name);
	}
    }
    return @fields;
}
    

# read binary data from file
sub read_from {
    my ($buf, $filename);
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    my ($hdrfile, $was_filename) = $self->_check_file('in', +shift);

    my $binlen = $self->{binlen};
    my $res = read($hdrfile, $buf, $binlen);
    croak "'$!' - could not read $binlen bytes from file" 
	if (!defined($res) || $res != $binlen);
    if ($was_filename) {
	close($hdrfile);
    }

    $self->binary_in($buf, @_);
}

sub write_to {
    my $buf;
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    my ($hdrfile, $was_filename) = $self->_check_file('out', +shift);
    $buf = $self->binary_out(@_);
    my $binlen = $self->{binlen};
    my $res = syswrite($hdrfile, $buf, $binlen);
    croak "'$!' - could not write $binlen bytes to file" 
	if (!defined($res) || $res != $binlen);
    if ($was_filename) {
	close($hdrfile);
    }
}

my %File_options = ('in' => {'line_char'=>'<',
			     'prompt'=>'source'},
		    'out' => {'line_char'=>'>',
			      'prompt'=>'output'}
		    );

sub _check_file {
    my ($was_filename, $filename, $filestore);
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need in or out specifier" unless (@_);
    my ($line_char, $prompt) = 
	@{$File_options{+shift}}{'line_char', 'prompt'}; 
    croak "Need $prompt for data" unless (@_);
    my $hdrfile = shift;
    if (!ref($hdrfile)) { # filename passed
	$was_filename = 0;
	$filename = $hdrfile;
	
	if ($self->{enforce_extension}) {
	    my $changef;
	    ($filename, $changef) = $self->replace_extension($filename);
	    warn "Changed filename $hdrfile to $filename" 
		if ($changef && $self->verbose());
	}
	open(HDR, "${line_char}$filename") or 
	    croak "Error '$!' opening file: $filename\n";
	$self->{filename} = $filename;
	$hdrfile = \*HDR;
    } else {
	$was_filename = 1;
    }
    binmode($hdrfile);
    return ($hdrfile, $was_filename);
}

# replace extension of filename with default
sub replace_extension {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need a file name" unless (@_);
    my $filename = shift;
    my $changef = 0;
    if (defined($self->{extension})) {
    	my ($n, $p, $e);
	($n, $p, $e)  = fileparse($filename, '\..*?');
	if ($e ne ('.' . $self->{extension})) {
	    $filename = join('',($p, $n, '.',$self->{extension}));
	    $changef = 1;
	}
    } else {
	warn "No extension set - cannot change extension" 
	    if ($self->{verbose});
    }
    return ($filename, $changef);
}

# hash field->method calls
sub endian {
    my $self = shift;
    return hashmethod($self, 'endian', @_);
}

sub hashmethod {
    my $self = shift;
    croak "$self is not an object" unless ref($self);
    croak "Need a hash name specifier" unless (@_);
    my $hname = shift;
    croak "No hash called $hname in object" 
	unless exists($self->{$hname}); 
    croak "$hname is not a hash reference in object"  
	unless (ref($self->{$hname}) eq 'HASH');

    return %{$self->{$hname}} unless (@_);
    my $name = shift;
    croak "No $name field in hash $hname" 
	unless (exists($self->{$hname}{$name}));
    if (@_) { $self->{$hname}{$name} = @_ }

    return $self->{$hname}{$name};
}

# ordinary field->method calls
sub verbose {
    my $self = shift;
    if (@_) { $self->{verbose} = @_ }
    return $self->{verbose};
}

sub extension {
    my $self = shift;
    if (@_) { $self->{extension} = @_ }
    return $self->{extension};
}

sub enforce_extension {
    my $self = shift;
    if (@_) { $self->{enforce_extension} = @_ }
    return $self->{enforce_extension};
}

sub filename {
    my $self = shift;
    if (@_) { $self->{filename} = @_ }
    return $self->{filename};
}

sub structure_array {
    my $self = shift;
    croak "structure array is read-only" if (@_);
    return $self->{starr};
}

sub structure_as_hash {
    my $self = shift;
    croak "structure as hash is read-only" if (@_);
    return $self->{stash};
}

sub binlen {
    my $self = shift;
    croak "binlen is a read-only field" if (@_);
    return $self->{binlen};
}
1;
