package PList::Threads::Binary;

use strict;
use warnings;

use base "PList::Threads";

use Storable;

sub new($$) {

	my ($class, $file) = @_;

	my $priv = {
		file => $file,
		emails => {},
		roots => {},
	};

	eval {
		my $hash = retrieve($file);
		$priv->{emails} = $hash->{emails};
		$priv->{roots} = $hash->{roots};
	};

	bless $priv, $class;

}

sub save($) {

	my ($priv) = @_;

	my $hash = {
		emails => $priv->{emails},
		roots => $priv->{roots},
	};

	my $ret = 0;

	eval {
		store($hash, $priv->{file});
		$ret = 1;
	};

	return $ret;

}

sub add_email($$$$$) {

	my ($priv, $id, $up, $file, $offset) = @_;

	my $emails = $priv->{emails};
	my $roots = $priv->{roots};

	my $email = $emails->{$id};

	if ( exists ${$emails}{$id} ) {

		# Email with ID is already there
		if ( not $email->{implicit} ) {
			return 0;
		}

		# Email with ID is not there, but other emails reference it
		$email->{up} = $up;
		$email->{file} = $file;
		$email->{offset} = $offset;
		$email->{implicit} = 0;

	} else {

		$email = {
			up => $up,
			down => [],
			file => $file,
			offset => $offset,
			implicit => 0,
		};

		$emails->{$id} = $email;

	}

	if ( not $up ) {
		$roots->{$id} = 1;
	} else {
		delete $roots->{$id};
	}

	if ( ref $up ) {
		foreach(@{$up}) {
			if ( $emails->{$_} ) {
				push(@{$emails->{$_}->{down}}, $id);
			} else {
				$emails->{$_} = {
					up => undef,
					down => [$id],
					file => undef,
					offset => 0,
					implicit => 1,
				};
				$roots->{$_} = 1;
			}
		}
	} elsif ( $up ) {
		if ( $emails->{$up} ) {
			push(@{$emails->{$up}->{down}}, $id);
		} else {
			$emails->{$up} = {
				up => undef,
				down => [$id],
				file => undef,
				offset => 0,
				implicit => 1,
			};
			$roots->{$up} = 1;
		}
	}

	return 1;

}

sub del_email($$) {

	my ($priv, $id) = @_;

	my $emails = $priv->{emails};
	my $roots = $priv->{roots};

	my $email = $emails->{$id};
	my $up = $email->{up};

	if ( not exists ${$emails}{$id} ) {
		return 0;
	}

	$email->{deleting} = 1;

	my $delete = 1;
	foreach ( @{$email->{down}} ) {
		if ( exists ${$emails}{$_} and not $emails->{$_}->{implicit} ) {
			$delete = 0;
			last;
		}
	}

	if ( not $delete ) {
		$email->{up} = undef;
		$email->{file} = undef;
		$email->{offset} = 0;
		$email->{implicit} = 1;
	} else {
		foreach ( @{$email->{down}} ) {
			if ( exists ${$emails}{$_} ) {
				$roots->{$_} = 1;
			}
		}
		delete $emails->{$id};
		if ( exists $roots->{$id} ) {
			delete $roots->{$id};
		}
	}

	if ( ref $up ) {
		foreach ( @{$up} ) {
			if ( exists ${$emails}{$_} ) {
				if ( $emails->{$_}->{implicit} and not $emails->{$_}->{deleting} ) {
					$priv->del_email($_);
				}
			}
			# TODO: delete $id from $emails->{$_}->{down}
		}
	} elsif ( $up ) {
		if ( exists ${$emails}{$up} ) {
			if ( $emails->{$up}->{implicit} and not $emails->{$up}->{deleting} ) {
				$priv->del_email($up);
			}
			# TODO: delete $id from $emails->{$up}->{down}
		}
	}

	delete $email->{deleting};

	return 1;

}

sub emails($) {

	my ($priv) = @_;
	return $priv->{emails};

}

sub roots($) {

	my ($priv) = @_;
	return $priv->{roots};

}

sub up($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{up};

}

sub down($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{down};

}

sub file($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{file};

}

sub offset($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{offset};

}

sub implicit($$) {

	my ($priv, $id) = @_;
	return $priv->{emails}->{$id}->{implicit};

}

1;
