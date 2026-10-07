import '../../models/models.dart';

/// Tabs on [TradeListScreen]. Kept public so extracted card/actions widgets
/// can key behavior without importing the screen state class (#496).
enum TradeTab { match_, offerOut, offerIn, active, completed }

/// Per-user completion: a match is in progress for the viewer while it is
/// ACCEPTED, or COMPLETED by the counterpart but not yet by the viewer.
bool isActiveForMe(TradeMatch m) =>
    m.status == 'ACCEPTED' || (m.status == 'COMPLETED' && !m.completedByMe);

/// Per-user completion: Done only once the viewer has completed it.
bool isCompletedForMe(TradeMatch m) =>
    m.status == 'COMPLETED' && m.completedByMe;
