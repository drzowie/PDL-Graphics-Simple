
######################################################################
######################################################################
######################################################################
###
###
### PGPLOT interface to PDL::Graphics::Simple.  
###
### See the PDL::Graphics::Simple docs for details
###
##
#

package PDL::Graphics::Simple::PGPLOT;

use File::Temp qw/tempfile/;
use PDL::Options q/iparse/;

use PDL;

our $mod = {
    shortname => 'pgplot',
    module=>'PDL::Graphics::Simple::PGPLOT',
    engine => 'PDL::Graphics::PGPLOT::Window',
    synopsis=> 'PGPLOT (old but trusted)',
    pgs_version=> '0.004'
};
PDL::Graphics::Simple::register( 'PDL::Graphics::Simple::PGPLOT' );

##########
# PDL::Graphics::Simple::PGPLOT::check
# Checker

sub check {
    my $force = shift;
    $force = 0 unless(defined($force));

    return $mod->{ok} unless( $force or !defined($mod->{ok}) );
    
    eval 'use PDL::Graphics::PGPLOT::Window;';
    if($@) {
	$mod->{ok} = 0;
	$mod->{msg} = $@;
	return 0;
    }
    
    # Module loaded OK, now try to extract valid devices from it
    my ($fh,$tf) = tempfile('pgg_pgplot_XXXX');
    close $fh;

    my $cmd = qq{|perl -e "use PGPLOT; open STDOUT,q[>$tf] || die; open STDERR,STDOUT || die; pgopen(q[?])"};
    open FOO,$cmd;
    print FOO "?\n";
    close FOO;
    open FOO,"<$tf";
    my @lines = grep /^\s+\//, (<FOO>) ;
    close FOO;
    unlink $tf;
    
    $mod->{devices} = { map { chomp; s/^\s*\///; s/\s.*//; ($_,1) } @lines };

    if( $mod->{devices}->{'XWINDOW'} ) {
	$mod->{disp_dev} = 'XWINDOW';
    } elsif($mod->{devices}->{'XSERVE'} ) {
	$mod->{disp_dev} = 'XSERVE';
    } else {
	$mod->{ok} = 0;
	return 0;
    }

    unless( $mod->{devices}->{'VCPS'} ) {
	$mod->{ok} = 0;
	return 0;
    }

    return 1;
}

##########
# PDL::Graphics::Simple::PGPLOT::new
our $new_defaults ={
    size => [8,6,'in'],
    type => '',
    output=>'',
    multi=>undef
};

our $filetypes = {
    png => 'PNG',
    ps  => 'VCPS'
};

sub new {
    my $pkg = shift;
    my $opt_in = shift;
    my $opt = { iparse( $new_defaults, $opt_in ) };
    
    my $pgw;
    
    # Force a recheck on failure, in case the user fixed PGPLOT.
    # Also loads PDL::Graphics::PGPLOT::Window.
    unless(check()) {
	die "$mod->{shortname} appears nonfunctional\n" unless(check(1));
    }

    # Figure the device name and size to feed to PGPLOT.
    # size has already been regularized.
    my $conv_tempfile;
    my $dev;

    if( $opt->{type} =~ m/^i/i) {
	$dev = ( defined($opt->{output}) ? $opt->{output} : "" ) . "/" . $mod->{disp_dev};
    } else {
	my $ext;

	if( $opt->{output} =~ m/\.(\w{2,4})$/ ) {
	    $ext = $1;
	} else {
	    $ext = 'png';
	    $opt->{output} .= ".png";
	}

	our $mod;
	unless(  $filetypes->{$ext}  and  $mod->{devices}->{$filetypes->{$ext}} ) {
	    my($fh);
	    ($fh, $conv_tempfile) = tempfile('pgs_pgplot_XXXX');
	    close $fh;
	    unlink $conv_tempfile; # just to be sure...
	    $conv_tempfile .= ".ps";
	    $dev = "$conv_tempfile/VCPS";
	} else {
	    $dev = "$opt->{output}/$filetypes->{$ext}";
	}
    }

    print "dev='$dev'\n";
    print "opt->size is ".join(",",@{$opt->{size}})."\n";

    ($ENV{'PGPLOT_PS_WIDTH'}) = $opt->{size}->[0] * 1000;
    ($ENV{'PGPLOT_PS_HEIGHT'}) = $opt->{size}->[1] * 1000;

    my @params = ( 'size => [$opt->{size}->[0], $opt->{size}->[1] ]' );
    if( defined($opt->{multi}) ) {
	push(@params, 'nx=>$opt->{multi}->[0]');
	push(@params, 'ny=>$opt->{multi}->[1]');
    }

    
    my $creator = 'pgwin( $dev, { '. join(",", @params) . '} );';
    $pgw = eval $creator;
    print STDERR $@ if($@);
    
    my $me = { opt=>$opt, conv_fn=>$conv_tempfile, obj=>$pgw };
    return bless($me, 'PDL::Graphics::Simple::PGPLOT');
}

our $pgplot_methods = {
    'lines'  => 'line',
    'bins'   => 'bin',
    'points' => 'points',
    'errorbars' => sub {
	my ($me, $ipo, $data, $ppo) = @_;
	$me->{obj}->points($data->[0],$data->[1],$ppo);
	$me->{obj}->errb($data->[0],$data->[1],$data->[2]);
    },
    'limitbars'=> sub {
	my ($me, $ipo, $data, $ppo) = @_;
	# use XY absolute error form, but with X errorbars right on the point
	$me->{obj}->points($data->[0],$data->[1],$ppo);
	my $z = zeroes($data->[0]);
	$me->{obj}->errb($data->[0],$data->[1], $z, $z, -($data->[2]-$data->[1]), $data->[3]-$data->[1], $ppo);
    },
    'image'  => 'imag',
    'circles'=> sub { 
	my ($me,$ipo,$data,$ppo) = @_;
	$ppo->{filltype}='outline';
	$me->{obj}->tcircle(@$data, $ppo);
    }
};

##############################
# PDL::Graphics::Simple::PGPLOT::plot

sub plot {
    my $me = shift;
    my $ipo = shift;
    my $po = {};
    $po->{title} = $ipo->{title}   if(defined($ipo->{title}));
    $po->{xtitle}= $ipo->{xtitle}  if(defined($ipo->{xtitle}));
    $po->{ytitle}= $ipo->{ytitle}  if(defined($ipo->{ytitle}));
    $po->{justify}=$ipo->{justify} if(defined($ipo->{justify})); 

    my %color_opts = ();
    if(defined($ipo->{crange})) {
	$color_opts{'MIN'} = $ipo->{crange}->[0] if(defined($ipo->{crange}->[0]));
	$color_opts{'MAX'} = $ipo->{crange}->[0] if(defined($ipo->{crange}->[1]));
    }
    
    my $more = 0;

    if($ipo->{oplot}  and   $me->{opt}->{type} =~ m/^f/i) {
	die "The PGPLOT engine does not yet support oplot for files.  Instead, \nglom all your lines together into one call to plot.\n";
    }

    $me->{obj}->release;
    $me->{obj}->env(@{$ipo->{xrange}}, @{$ipo->{yrange}}, $po);
    $me->{obj}->hold;

    warn "P::G::S::PGPLOT: key not implemented yet" if($ipo->{key});


    # ppo is "post-plot options", which are really a mix of plot and curve options.  
    # Currently we don't parse any plot options into it (they're handled by the "env"
    # call) but if we end up doing so, it should go here.  The linestyle and color
    # are curve options that are autoincremented each curve.
    my %ppo = ();
    my $ppo = \%ppo;
    
    $ppo->{linestyle} = 1;
    $ppo->{color}=1;
    
    while(@_) {
	my ($co, @data) = @{shift()};
	my @extra_opts = ();

	our $pgplot_methods;
	my $pgpm = $pgplot_methods->{$co->{with}};
	die "Unknown curve option 'with $co->{with}'!" unless($pgpm);


	if($pgpm eq 'imag') {
	    for my $k(keys %color_opts) {
		$po->{$k} = $color_opts{$k};
	    }

	    # Extract transform parameters from the corners of the image...
	    my $xcoords = shift(@data);
	    my $ycoords = shift(@data);

	    my $datum_pix = [0,0];
	    my $datum_sci = [$xcoords->at(0,0), $ycoords->at(0,0)];
	    
	    my $t1 = ($xcoords->slice("(-1),(0)") - $xcoords->slice("(0),(0)")) / ($xcoords->dim(0)-1);
	    my $t2 = ($xcoords->slice("(0),(-1)") - $xcoords->slice("(0),(0)")) / ($xcoords->dim(1)-1);
	    
	    my $t4 = ($ycoords->slice("(-1),(0)") - $ycoords->slice("(0),(0)")) / ($ycoords->dim(0)-1);
	    my $t5 = ($ycoords->slice("(0),(-1)") - $ycoords->slice("(0),(0)")) / ($ycoords->dim(1)-1);
	    
	    my $transform = pdl(
		$datum_sci->[0] - $t1 * $datum_pix->[0] - $t2 * $datum_pix->[1],
		$t1, $t2,
		$datum_sci->[1] - $t4 * $datum_pix->[0] - $t5 * $datum_pix->[1],
		$t4, $t5
		)->flat;

	    {   # sepia color table
		my $r = (xvals(256)/255)->sqrt;
		my $g = (xvals(256)/255);
		my $b = (xvals(256)/255)**2;
		$me->{obj}->ctab($g, $r, $g, $b);
	    }
	}

	if(ref($pgpm) eq 'CODE') {
	    &$pgpm($me, $ipo, \@data, $ppo);
	} else {
	    my $str= sprintf('$me->{obj}->%s(@data,%s);%s',$pgpm,'$ppo',"\n");
	    eval $str;
	}

	unless($pgpm eq 'imag') {
	    $ppo->{linestyle}++;
	    $ppo->{color}++;
	}

	$me->{obj}->hold;
    }
    $me->{obj}->release;
    $me->{obj}->close if($me->{opt}->{type} =~ m/^f/i  and !defined($me->{opt}->{multi}));

    my $file = ( ($me->{conv_fn}) ? $me->{conv_fn} : $me->{output} );
    if(defined($file) and $file =~ m/\.ps$/) {
	## PGPLOT PS files are malformed - the BoundingBox notations break the spec, so the
	## rim/wim technique doesn't work.  Patch up the PS file to have a correct BoundingBox.

	open FOO, "<$file";
	my @lines = <FOO>;
	my $i;
	
	for($i=0; $i<@lines; $i++) {

	    if($lines[$i] =~ m/^\%\%BoundingBox: \(atend\)/) {
		$lines[$i] = sprintf("%%%%BoundingBox: 35 35 %d %d\n", 
				     35 + 72 * $me->{opt}->{size}->[0], 
				     35 + 72 * $me->{opt}->{size}->[1]);
	    } elsif( $lines[$i] =~ m/^\%\%BoundingBox:/ ) {
		$lines[$i] = "%%\n";
	    } elsif( $lines[$i] =~ m/^\%\%PageBoundingBox:/) {
		$lines[$i] = sprintf("%%%%PageBoundingBox: 35 35 %d %d\n", 
				     35 + 72 * $me->{opt}->{size}->[0], 
				     35 + 72 * $me->{opt}->{size}->[1]);
	    }
	}
	open FOO,">$file";
	print FOO join("",@lines);
    };

    if($me->{conv_fn}) {
	$a = rim($me->{conv_fn});
	wim($a, $me->{opt}->{output});
	unlink($me->{conv_fn});
    } 
}
