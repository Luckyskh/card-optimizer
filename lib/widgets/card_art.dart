/// Draws a small stylised picture of each credit card.
///
/// These are **mock cards, drawn by this code** — a rounded rectangle, a chip,
/// a colour scheme and the card's name. They are not the issuers' artwork.
///
/// That is deliberate on two counts. The issuers' terms PDFs turn out to
/// contain no card images at all — they are legal documents, and the only
/// pictures inside them are alpha-mask blobs a millimetre across. And even
/// where artwork is available on a bank's website, it is their trademarked
/// brand asset, which is not something to bundle into an app.
///
/// Drawing them instead means every card gets a picture, including the five
/// HDFC cards whose pages refuse automated requests, and it keeps working
/// offline with nothing to download.
library;

import 'package:flutter/material.dart';

import '../models/card.dart';

/// The two colours a card is drawn with.
class CardPalette {
  final Color start;
  final Color end;

  /// Colour for the text and chip drawn on top.
  final Color foreground;

  const CardPalette(this.start, this.end, {this.foreground = Colors.white});

  /// Picks a look for a card.
  ///
  /// Co-branded cards take their partner's colours, because that is how people
  /// recognise them — nobody thinks of the Swiggy card as an HDFC card. Cards
  /// without a partner fall back to their issuer's scheme, so the ones you own
  /// stay visually distinct from each other in a list.
  factory CardPalette.forCard(CardRule card) {
    const byCard = <String, CardPalette>{
      // Co-brands, by their partner's colours.
      'swiggy-ornge-hdfc':
          CardPalette(Color(0xFFFC8019), Color(0xFFB3560F)),
      'swiggy-blck-hdfc': CardPalette(Color(0xFF2B2B2E), Color(0xFF0A0A0B)),
      'amazon-pay-icici':
          CardPalette(Color(0xFF232F3E), Color(0xFF131A22)),
      'flipkart-axis': CardPalette(Color(0xFF2874F0), Color(0xFF11407F)),
      'tata-neu-infinity-hdfc':
          CardPalette(Color(0xFF5B2C87), Color(0xFF2E1547)),

      // Premium tiers, which are dark or metallic in real life.
      'axis-atlas': CardPalette(Color(0xFF1C2B4A), Color(0xFF0A1122)),
      'hdfc-regalia-gold':
          CardPalette(Color(0xFFB68A3C), Color(0xFF6B4E1C)),
    };

    final specific = byCard[card.id];
    if (specific != null) return specific;

    const byBank = <String, CardPalette>{
      'HDFC Bank': CardPalette(Color(0xFF00579B), Color(0xFF00294D)),
      'SBI Card': CardPalette(Color(0xFF1B3A93), Color(0xFF0E1F4F)),
      'Axis Bank': CardPalette(Color(0xFF97144D), Color(0xFF4E0A28)),
      'ICICI Bank': CardPalette(Color(0xFFAE2A26), Color(0xFF6B1512)),
      'IDFC FIRST Bank': CardPalette(Color(0xFF9C1D2A), Color(0xFF4E0E15)),
    };

    return byBank[card.bank] ??
        const CardPalette(Color(0xFF455A64), Color(0xFF263238));
  }
}

/// A drawn mock of one credit card.
///
/// Everything scales from [width], so the same widget works as a 52-pixel row
/// thumbnail and as a larger picture, and real cards are always the same shape
/// — 85.6 by 54 millimetres, which is the 1.586 ratio used below.
class CardArt extends StatelessWidget {
  final CardRule card;
  final double width;

  /// Draws a ring around the card. Used to mark the recommended one.
  final bool highlighted;

  const CardArt({
    super.key,
    required this.card,
    this.width = 52,
    this.highlighted = false,
  });

  static const _aspectRatio = 1.586;

  @override
  Widget build(BuildContext context) {
    final palette = CardPalette.forCard(card);
    final height = width / _aspectRatio;
    final radius = width * 0.09;

    // Below this size any text is a smudge, so the card is drawn as colour and
    // chip only. Above it there is room for the bank's initials.
    final showsText = width >= 76;

    return Semantics(
      // Screen readers should hear the card's name, not "image".
      label: card.displayName,
      image: true,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.start, palette.end],
          ),
          border: highlighted
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: width * 0.035,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: width * 0.06,
              offset: Offset(0, width * 0.02),
            ),
          ],
        ),
        child: Stack(
          children: [
            // A soft highlight across the top, which is what stops the card
            // reading as a plain coloured rectangle.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // The chip.
            Positioned(
              left: width * 0.11,
              top: height * 0.30,
              child: Container(
                width: width * 0.17,
                height: width * 0.13,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width * 0.025),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF2D98B), Color(0xFFC9A44C)],
                  ),
                ),
              ),
            ),

            if (showsText)
              Positioned(
                left: width * 0.11,
                bottom: height * 0.12,
                right: width * 0.11,
                child: Text(
                  card.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: width * 0.085,
                    fontWeight: FontWeight.w700,
                    letterSpacing: width * 0.004,
                  ),
                ),
              ),

            // The payment network, bottom right, as the two overlapping
            // circles everyone recognises.
            Positioned(
              right: width * 0.09,
              top: height * 0.30,
              child: _NetworkMark(
                network: card.network.isEmpty ? '' : card.network.first,
                size: width * 0.14,
                color: palette.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The little payment-network mark in the corner.
class _NetworkMark extends StatelessWidget {
  final String network;
  final double size;
  final Color color;

  const _NetworkMark({
    required this.network,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Mastercard and RuPay both read as interlocking circles at this size;
    // Visa is usually just the wordmark, so a single circle stands in.
    final isTwoCircles = network == 'mastercard' || network == 'rupay';

    return SizedBox(
      width: isTwoCircles ? size * 1.6 : size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _Circle(size: size, color: color.withValues(alpha: 0.85)),
          ),
          if (isTwoCircles)
            Positioned(
              left: size * 0.6,
              child: _Circle(size: size, color: color.withValues(alpha: 0.5)),
            ),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final Color color;

  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
