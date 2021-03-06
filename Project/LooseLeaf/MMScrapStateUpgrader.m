//
//  MMScrapStateUpgrader.m
//  LooseLeaf
//
//  Created by Adam Wulf on 6/1/16.
//  Copyright © 2016 Milestone Made, LLC. All rights reserved.
//

#import "MMScrapStateUpgrader.h"
#import "MMScrappedPaperView.h"
#import "MMScrapCollectionState.h"
#import "MMImmutableScrapsOnPaperState.h"


@interface MMScrapStateUpgrader () <MMScrapsOnPaperStateDelegate>

@end


@implementation MMScrapStateUpgrader {
    NSString* pagesPath;
}

- (instancetype)initWithPagesPath:(NSString*)_pagesPath {
    if (self = [super init]) {
        pagesPath = _pagesPath;
    }
    return self;
}

- (NSString*)scrapIDsPath {
    return [[pagesPath stringByAppendingPathComponent:@"scrapIDs"] stringByAppendingPathExtension:@"plist"];
}

- (void)upgradeWithCompletionBlock:(void (^)())onComplete {
    CheckMainThread;
    @autoreleasepool {
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self scrapIDsPath]]) {
            CGRect screenBounds = [[[UIScreen mainScreen] fixedCoordinateSpace] bounds];
            MMScrapsOnPaperState* state = [[MMScrapsOnPaperState alloc] initWithDelegate:self withScrapContainerSize:screenBounds.size];

            [state loadStateAsynchronously:NO atPath:[self scrapIDsPath] andMakeEditable:NO andAdjustForScale:YES];

            MMImmutableScrapCollectionState* immutableScrapState = [state immutableStateForPath:[self scrapIDsPath]];
            dispatch_async([MMScrapCollectionState importExportStateQueue], ^{
                [immutableScrapState saveStateToDiskBlocking];

                // unloading the scrap state will also remove them
                // from their superview (us)
                [state unloadPaperState];

                dispatch_async(dispatch_get_main_queue(), onComplete);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), onComplete);
        }
    }
}

#pragma mark - MMScrapViewOwnershipDelegate

- (MMScrapView*)scrapForUUIDIfAlreadyExistsInOtherContainer:(NSString*)scrapUUID {
    return nil;
}

#pragma mark - MMScrapCollectionStateDelegate


- (NSString*)uuidOfScrapCollectionStateOwner {
    return [pagesPath lastPathComponent];
}

- (void)didLoadScrapInContainer:(MMScrapView*)scrap {
    // noop
}

- (void)didLoadScrapOutOfContainer:(MMScrapView*)scrap {
    // noop
}

- (void)didLoadAllScrapsFor:(MMScrapCollectionState*)scrapState {
    // noop
}

- (void)didUnloadAllScrapsFor:(MMScrapCollectionState*)scrapState {
    // noop
}


#pragma mark - MMScrapsOnPaperStateDelegate;

- (MMScrappedPaperView*)page {
    return nil;
}

- (BOOL)isEditable {
    return NO;
}

- (NSString*)pagesPath {
    return pagesPath;
}

- (NSString*)bundledPagesPath {
    return nil;
}

#pragma mark - Scrap Container for Sidebar

- (void)deleteScrapWithUUID:(NSString*)scrapUUID shouldRespectOthers:(BOOL)respectOthers {
    // noop
}

@end
