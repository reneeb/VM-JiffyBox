package VM::JiffyBox;

# The line below is recognised by Dist::Zilla and taken for CPAN packaging
# ABSTRACT: OO-API for JiffyBox Virtual Machine

use Moo;
use JSON;
use LWP::UserAgent;

use VM::JiffyBox::Box;

has domain_name => (is => 'rw', default => sub {'https://api.jiffybox.de'});
has version     => (is => 'rw', default => sub {'v1.0'});
has token       => (is => 'rw', required => 1);

has ua          => (is => 'rw', default => sub {LWP::UserAgent->new()});

has test_mode   => (is => 'rw', default => sub {'0'});

# should always keep the last message from the server
has last          => (is => 'rw');
has details_cache => (is => 'rw');

sub base_url {
    my $self = shift;

    return   $self->domain_name . '/'
           . $self->token       . '/' 
           . $self->version     ;
}

sub get_details {
    my $self = shift;
    
    my $url = $self->base_url . '/jiffyBoxes';
    
    my $response = $self->ua->get($url);

    # POSSIBLE EXIT
    unless ($response->is_success) {
        $self->last ($response->status_line);
        return 0;
    }

    my $details = from_json($response->decoded_content);

    $self->last         ( $details );
    $self->details_cache( $details );

    return $details;
}

sub get_id_from_name {
    my $self = shift;
    my $box_name = shift || '';
    
    my $details = $self->get_details;

    $self->last         ( $details );
    $self->details_cache( $details );
    
    foreach my $box (values %{$details->{result}}) {
        return $box->{id} if ($box->{name} eq $box_name);
    }
}

sub get_vm {
    my $self   = shift;
    my $box_id = shift || die 'box_id needed';

    my $box = VM::JiffyBox::Box->new(id => $box_id);

    # set the hypervisor of the VM
    $box->hypervisor($self);

    return $box;
}

sub create_vm {
    my $self = shift;
    my $name = shift || '';
    my $plan_id = shift || 0;
    my $backup_id = shift || 0;
    
    my $url = $self->base_url . '/jiffyBoxes';
    
    my $response = $self->ua->post( $url,
                                    Content => to_json(
                                      {
                                        name     => $name,
                                        planid   => $plan_id,
                                        backupid => $backup_id,
                                      }
                                    )
                                  );

    # POSSIBLE EXIT
    unless ($response->is_success) {
        $self->last ($response->status_line);
        return 0;
    }

    $self->last ( from_json($response->decoded_content) );

    # POSSIBLE EXIT
    # TODO: should check the array for more messages
    if (exists $self->last->{messages}->[0]->{type}
        and    $self->last->{messages}->[0]->{type} eq 'error') {
        return 0;
    }

    my $box_id = $self->last->{result}->{id};
    my $box = VM::JiffyBox::Box->new(id => $box_id);

    # set the hypervisor of the VM
    $box->hypervisor($self);

    return $box;
}

1;

__END__

=encoding utf8

=head1 SYNOPSIS

 #############################
 # CREAT A CLONE FROM BACKUP #
 #############################
 
 # stuff we need to know our self
 my $auth_token = $ARGV[0];
 my $box_name   = $ARGV[1];
 my $clone_name = $ARGV[2];
 
 # prepare connection to VM-Server
 my $jiffy = VM::JiffyBox->new(token => $auth_token); 
 
 # translate VM-Name (String) to ID (Number)
 my $master_box_id = $jiffy->get_id_from_name($box_name);
 
 say "master_box_id: $master_box_id";
 
 # prepare connection to the VM
 my $master_box = $jiffy->get_vm($master_box_id);
 
 # collect information about the VM
 my $backup_id  = $master_box->get_backups()->{result}->{daily}->{id};
 my $plan_id    = $master_box->get_details()->{result}->{plan}->{id};
 
 say "backup_id: $backup_id";
 say "plan_id: $plan_id";
 
 # create a clone of the VM
 my $clone_box  = $jiffy->create_vm( $clone_name, $plan_id, $backup_id );
 
 # abort if create failed
 unless ($clone_box) {
     # FAIL
     die $jiffy->last->{messages}->[0]->{message};
 }
 
 # wait for the clone to be ready
 do {
     say "waiting for clone to get READY";
     sleep 15; 
 } while (not $clone_box->get_details->{result}->{status} eq 'READY');
 
 # start the clone
 $clone_box->start();

(See the C<examples> directory for more examples of working code.)

=head1 ERROR HANDLING

All methods will return C<0> on failure, so you can check for this with a simple C<if> on the return value.
If you need the error message you can use the cache and look into the attribute C<last>.
The form of the message is open.
It can contain a simple string, or also a hash.
This depends on the kind of error.
So if you want to be sure, just use L<Data::Dumper> to print it.

=head1 CACHING

There are possibilities to take advantage of caching functionality.
If you have once called get_details(), the results will be stored in the attribute C<details_cache>.

=head1 METHODS

=head2 get_details

Returns hashref with information about the hypervisor and its virtual machines.
Takes no arguments.

Results are cached in C<details_cache>.

=head2 get_id_from_name

Returns the ID for a specific virtual machine.
Takes the name for the virtual machine as first argument.

(Also updates the C<details_cache>)

=head2 get_vm

Returns an object-ref to an existing virtual machine (L<VM::JiffyBox::Box>).
Takes the ID for the virtual machine as first argument.

=head2 create_vm

Creates a new virtual machine and returns an object-ref to it (L<VM::JiffyBox::Box>).
Takes 3 arguments:

=over

=item 1

name: The name for the new VM.

=item 2

plan_id: The ID for pricing.

=item 3

backup_id: Name of the backup-image to take.

=back

B<Note:> This methods interface could change in future releases, since it does not yet cover full functionality.

=head1 SEE ALSO

=over

=item *

Source, contributions, patches: L<https://github.com/tim-schwarz/VM-JiffyBox>

=item *

This module is B<not> officially supported by or related to the company I<domainfactory> in Germany.
However it aims to provide an interface to the API of their product I<JiffyBox>.
So to use this module with success you should also B<read their API-Documentation>, available for registered users of their service.

=back

