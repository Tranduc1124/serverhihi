#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class TserverSimpleUiPackBase;

#ifdef __cplusplus
extern "C" {
#endif

UIFont *TCTFont(CGFloat size);
UILabel *TCTLine(TserverSimpleUiPackBase *pack, NSString *text, UIColor *color, CGFloat size);
void TCTAppendLine(TserverSimpleUiPackBase *pack, NSString *text, UIColor *color);
void TCTTypeLines(TserverSimpleUiPackBase *pack, NSArray<NSString *> *lines, NSArray<UIColor *> *colors, NSTimeInterval gap);

#ifdef __cplusplus
}
#endif
