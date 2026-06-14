/// Ein Nextcloud-Principal (Benutzer) als Ziel einer Freigabe.
class Principal {
  const Principal({
    required this.shareHref,
    required this.displayName,
    this.email,
  });

  /// Href zum Freigeben im sabre/dav-Format, z.B.
  /// `principal:principals/users/bob`.
  final String shareHref;
  final String displayName;
  final String? email;
}

/// Eine bestehende Freigabe einer Collection.
class CollectionShare {
  const CollectionShare({
    required this.shareHref,
    required this.displayName,
    required this.readWrite,
  });

  final String shareHref;
  final String displayName;

  /// `true` = Schreibrechte, `false` = nur lesen.
  final bool readWrite;
}
