package Mojolicious::Plugin::Google::Cloud::UserAgent;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JWT::Google;

our $VERSION = '0.01';

has oauth_url     => 'https://www.googleapis.com/oauth2/v4/token';
has grant_type    => 'urn:ietf:params:oauth:grant-type:jwt-bearer';
has web_token     => undef;
has web_token_enc => undef;

sub register {
    my ($self, $app, $config) = @_;

    $app->helper(
        jwt => sub {
            my $c = shift;
            my $scopes = shift // $config->{scopes};

            Mojo::JWT::Google->new(
                from_json  => $config->{gcp_auth_file},
                target     => $config->{oauth_url} // $self->oauth_url,
                scopes     => Mojo::Collection->new($scopes)->flatten,
                issue_at   => time,
                expires_in => $config->{duration} // 3600
            );
        }
    );

    $app->helper(
        gcp_ua => sub {
            my $c      = shift;
            my $err_cb = pop;
            my $cb     = pop;
            my @args   = @_;

            if (!$self->web_token
                or ($self->web_token->issue_at + $self->web_token->expires_in) < time)
            {
                $self->web_token($c->jwt);
                $self->web_token_enc($self->web_token->encode);
            }

            Mojo::IOLoop::Delay->new->steps(
                sub {
                    my $d = shift;
                    $c->ua->post(
                        $self->oauth_url,
                        form => {
                            grant_type => $config->{grant_type} // $self->grant_type,
                            assertion => $self->web_token_enc
                        },
                        $d->begin
                    );
                },

                sub {
                    my $d  = shift;
                    my $tx = pop;

                    unless ($tx->res->json('/access_token')) {
                        return $err_cb->($tx, $c);
                    }

                    $d->pass($tx->res->json);
                },

                sub {
                    my $d     = shift;
                    my $token = pop;

                    my $tx = $c->ua->transactor->tx(@args);
                    $tx->req->headers->header(Authorization => $token->{token_type} . ' ' . $token->{access_token});
                    $c->ua->start($tx, $d->begin);
                },

                sub {
                    my $d = shift;
                    $cb->(@_);
                }
            );
        }
    );
}

1;
__END__

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Google::Cloud::UserAgent - A user agent for GCP

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('Google::Cloud::UserAgent');

  # Mojolicious::Lite
  plugin 'Google::Cloud::UserAgent' => {
    gcp_auth_file => $ENV{GCP_AUTH_FILE},
    scopes        => ['https://www.googleapis.com/auth/pubsub'],
    duration      => 3600
  };

  # in a controller
  get '/' => sub {
    my $c = shift;
    $c->render_later;

    $c->app->gcp_ua(GET => "https://pubsub.googleapis.com/v1/$ENV{GCP_PROJECT}/eig-nextgen/topics",
                    sub {  ## response handler
                        my ($ua, $tx) = @_;
                        $c->render(json => $tx->res->json, status => $tx->res->code);
                    },
                    sub {  ## error sub
                        my ($tx, $c) = @_;
                        $c->render(json => $tx->res->json, status => $tx->res->code);
                    }
    );
  };

=head1 DESCRIPTION

L<Mojolicious::Plugin::Google::Cloud::UserAgent> is a L<Mojolicious>
plugin for interacting with Google Cloud Platform. It performs
2-legged OAuth described here:
L<https://cloud.google.com/docs/authentication>.

First, create a service account key:

    L<https://console.cloud.google.com/apis/credentials?project=your-project>

Download this JSON file; you may hard-code the path to the JSON
service account key file when you load this plugin, or set an
environment variable, etc.

Next, determine the proper scopes for the user agent. Each GCP API has
a section in its documentation describing the scopes required to
invoke the API. For example, here is the Logging API scopes:

L<https://cloud.google.com/logging/docs/api/tasks/authorization>

Once you have these two items, pass them to the plugin as
configuration:

   plugin 'Google::Cloud::UserAgent' => {
     gcp_auth_file => $ENV{GCP_AUTH_FILE},
     scopes        => ['https://www.googleapis.com/auth/logging.write',
                       'https://www.googleapis.com/auth/logging.read'],
   };

=head1 METHODS

L<Mojolicious::Plugin::Google::Cloud::UserAgent> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register plugin in L<Mojolicious> application.

=head2 gcp_ua

  $c->app->gcp_ua(POST => $gcp_url, $cb, $error_cb);

Makes a non-blocking HTTP request of the given method to the given GCP
url. If the OAuth step succeeds, the C<$cb> callback will be invoked
and passed the user agent object and the transaction
object. Otherwise, the C<$error_cb> will be invoked and passed the
controller object and the transaction object of the OAuth request.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
