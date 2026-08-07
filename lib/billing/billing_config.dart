/// Master switch for paid features.
///
/// 1.0 ships free: the subscription plumbing (see `pro_service.dart` and
/// `paywall.dart`) is written and tested but deliberately dormant, because
/// selling anything requires Apple's Paid Apps agreement to be signed first.
///
/// To turn TERRAX Pro on in a later release: sign the Paid Apps agreement,
/// create the `com.terraxtech.app.pro.yearly` subscription in App Store
/// Connect, then flip this to true. Nothing else needs changing — the gates
/// and the paywall entry point read this flag.
const bool kSubscriptionsEnabled = false;
