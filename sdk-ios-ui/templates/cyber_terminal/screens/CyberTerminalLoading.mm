#import "TserverSimpleUiPack.h"
#import "../CyberTerminalPrivate.h"

void TserverCyberTerminalBuildLoading(TserverSimpleUiPackBase *pack) {
    NSString *title = [pack screenString:@"title" fallback:@"Dang kiem tra key"];
    NSString *subtitle = [pack screenString:@"subtitle" fallback:@"Vui long cho..."];
    if ([pack isCompactLandscape]) {
        TCTAppendLine(pack, @"> ./scan --package --lease", [pack accentColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> task: %@", title], [pack mutedTextColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> note: %@", subtitle], [pack mutedTextColor]);
        TCTAppendLine(pack, @"> ████████░░░░ 62%", [pack successColor]);
        return;
    }
    TCTTypeLines(pack,
        @[
            @"> ./scan --package --device --lease",
            [NSString stringWithFormat:@"> task: %@", title],
            [NSString stringWithFormat:@"> note: %@", subtitle],
            @"> running",
            @"> ████████░░░░ 62%"
        ],
        @[ [pack accentColor], [pack mutedTextColor], [pack mutedTextColor], [pack accentColor], [pack successColor] ],
        0.06);
}
