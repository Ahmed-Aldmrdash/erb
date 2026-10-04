import 'dart:io';

/// Which machine the app is running on.
///
/// The showroom runs on phones, and the owner also wants it on his laptop to
/// work faster with a keyboard and a real printer. A few things only a phone
/// has — the camera that reads a barcode, the photo that reads sack weights,
/// the contacts list — are hidden on the laptop instead of failing when they
/// are tapped. A USB barcode reader on the laptop still works everywhere,
/// because it types the code in like a keyboard.
bool get isMobile => Platform.isAndroid || Platform.isIOS;

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
