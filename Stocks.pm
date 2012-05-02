package Bot::BasicBot::Pluggable::Module::Stocks;
$Bot::BasicBot::Pluggable::Module::Stocks::VERSION = '1.00';
use base qw(Bot::BasicBot::Pluggable::Module);
use warnings;
use strict;
use JSON::XS
require HTTP::Request;
require LWP::UserAgent;
sub help {
  return 'Play the stock market! Try "buy/sell N of ABCD", "check ABCD", "stocks", "cash"';
}

sub init {
  my $self = shift;
  $self->set('url' => 'http://finance.yahoo.com/d/quotes.csv?s=%s&f=sl1cn');
}

sub told {
  my ($self, $mess) = @_;
  my $body = $mess->{body};
  my $who = $mess->{who};
  my $json = JSON::XS->new->ascii->allow_nonref;
  my $cash = $self->get('stocks_cash');
  $json->allow_nonref(1);
  if ($body =~ /^!clear stocks i am sure/) {
    $self->set('stocks', '');
    $self->set('stocks_cash', {});
    return 'Cleared.';
  }

  if ($body =~ /^cash$/) {
    if ($cash->{$who} == 0) {
      $cash->{$who} = 10000;
    }
    $self->set('stocks_cash', $cash);
    return "You have \$$cash->{$who}.";
  }

  if ($body =~ /^stocks/) {
    my $ref = $json->decode($self->get('stocks'));
    my @orders = @$ref;
    my $out;
    for my $order (@orders) {
      if ($order->{user} eq $who) {
        $out .= "$order->{qty}x$order->{stock}\@$order->{price} ";
      }
    }
    if ($out eq "") {
      return "No orders.";
    }
    return $out;
  }

  if ($body =~ /^check ([\w\.]+)$/) {
    my @price = $self->price($1);
    return $price[0] . ' ' . $price[1] . ' ' . $price[2];
  }

  if ($body =~ /^buy (\d+) of ([\w\.]+)/) {
    my $what = uc($2);
    my $qty = $1;
    my @orders;
    if ($self->get('stocks') ne "") {
      my $orders_ref;
      $orders_ref = $json->decode($self->get('stocks'));
      @orders = @$orders_ref;
    }

    my @values_price = $self->price($what);
    my $price = $values_price[1];
    if ($price <= 0) {
      return "Stock \"$what\" does not exist.";
    }

    if ($cash->{$who} eq "") {
      $cash->{$who} = 10000;
    }

    if ($price*$qty > $cash->{$who}) {
      return "Not enough cash.";
    }
    else {
      $cash->{$who} -= $price*$qty;
    }

    my %new_order = (
      'stock' => $what,
      'price' => $price,
      'user' => $who,
      'qty' => $qty,
    );

    push @orders, {%new_order};

    my $result = $json->encode(\@orders);

    $self->set('stocks', $result);
    $self->set('stocks_cash', $cash);
    return "Stock order fulfilled. You have \$$cash->{$who}";
  }

  if ($body =~ /^sell (\d+) of ([\w\.]+)/) {
    my $what = uc($2);
    my @price_arr = $self->price($what);
    my $price = $price_arr[1];
    my $qty = $1;
    my @orders;
    if ($self->get('stocks') ne "") {
      my $orders_ref;
      $orders_ref = $json->decode($self->get('stocks'));
      @orders = @$orders_ref;
    }

    my $out;
    for my $order (@orders) {
      if ($order->{user} eq $who && $order->{stock} eq $what) {
        # Run out the qtys on the orders
        if ($qty >= $order->{qty}) {
          $qty -= $order->{qty};
          $cash->{$who} += $order->{qty}*$price;
          if ($order->{qty} > 0) {
            $out .= "Sold $order->{qty}x$what\@$price ";
          }
          $order->{qty} = 0;
          undef($order);
        }
        elsif ($qty < $order->{qty}) {
          $order->{qty} -= $qty;
          $cash->{$who} += $qty*$price;
          if ($qty > 0) {
            $out .= "Sold ${qty}x$what\@$price ";
          }
          $qty = 0;
        }
      }
    }

    my $result = $json->encode(\@orders);

    $self->set('stocks', $result);
    $self->set('stocks_cash', $cash);

    return $out . " You have \$$cash->{$who}";
  }
}

sub price {
  my ($self, $symbol) = @_;
  my $url = sprintf($self->get("url"), $symbol);
  my $request = HTTP::Request->new(GET => $url);
  my $ua = LWP::UserAgent->new;
  my $response = $ua->request($request);
  my $content = $response->content();
  my @values = split(",", $content);
  return @values;
}
