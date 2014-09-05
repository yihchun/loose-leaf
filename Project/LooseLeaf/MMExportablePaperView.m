//
//  MMExportablePaperView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/28/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMExportablePaperView.h"
#import "NSFileManager+DirectoryOptimizations.h"
#import <ZipArchive/ZipArchive.h>


@implementation MMExportablePaperView{
    BOOL isCurrentlyExporting;
    BOOL isCurrentlySaving;
    BOOL waitingForExport;
    BOOL waitingForSave;
}


-(void) saveToDisk{
    @synchronized(self){
        if(isCurrentlySaving || isCurrentlyExporting){
            waitingForSave = YES;
            return;
        }
        isCurrentlySaving = YES;
        waitingForSave = NO;
    }
    [super saveToDisk];
}

-(void) saveToDisk:(void (^)(BOOL))onComplete{
    [super saveToDisk:^(BOOL hadEditsToSave){
        @synchronized(self){
            isCurrentlySaving = NO;
            [self retrySaveOrExport];
        }
        if(onComplete) onComplete(hadEditsToSave);
    }];
}

-(void) retrySaveOrExport{
    if(waitingForSave){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self saveToDisk];
        });
    }else if(waitingForExport){
        [self exportAsynchronouslyToZipFile];
    }
}

-(void) exportAsynchronouslyToZipFile{
    @synchronized(self){
        if(isCurrentlySaving || isCurrentlyExporting){
            waitingForExport = YES;
            return;
        }
        isCurrentlyExporting = YES;
        waitingForExport = NO;
    }
    if([self hasEditsToSave]){
        NSLog(@"saved exporing while save is still needed");
        [self saveToDisk];
        return;
    }
    
    dispatch_async([self serialBackgroundQueue], ^{
        NSString* generatedZipFile = [self generateZipFile];
        
        @synchronized(self){
            isCurrentlyExporting = NO;
            if(generatedZipFile){
                [self.delegate didExportPage:self toZipLocation:generatedZipFile];
            }else{
                [self.delegate didFailToExportPage:self];
            }
            [self retrySaveOrExport];
        }
    });
}



-(NSString*) generateZipFile{
    
    NSString* pathOfPageFiles = [self pagesPath];
    
    NSUInteger hash1 = self.paperState.lastSavedUndoHash;
    NSUInteger hash2 = self.scrapsOnPaperState.lastSavedUndoHash;
    NSString* zipFileName = [NSString stringWithFormat:@"%@%lu%lu.zip", self.uuid, (unsigned long)hash1, (unsigned long)hash2];
    
    NSString* fullPathToZip = [NSTemporaryDirectory() stringByAppendingPathComponent:zipFileName];
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:fullPathToZip]){
        NSString* fullPathToTempZip = [fullPathToZip stringByAppendingPathExtension:@"temp"];
        // make sure temp file is deleted
        [[NSFileManager defaultManager] removeItemAtPath:fullPathToTempZip error:nil];
        
        NSMutableArray* directoryContents = [[NSFileManager defaultManager] recursiveContentsOfDirectoryAtPath:pathOfPageFiles filesOnly:YES].mutableCopy;
        NSMutableArray* bundledContents = [[NSFileManager defaultManager] recursiveContentsOfDirectoryAtPath:[self bundledPagesPath] filesOnly:YES].mutableCopy;

        [bundledContents removeObjectsInArray:directoryContents];
        NSLog(@"generating zip file for path %@", pathOfPageFiles);
        NSLog(@"contents of path %d vs %d", (int) [directoryContents count], (int) [bundledContents count]);
        
        ZipArchive* zip = [[ZipArchive alloc] init];
        if([zip createZipFileAt:fullPathToTempZip])
        {
            for(int filesSoFar=0;filesSoFar<[directoryContents count];filesSoFar++){
                NSString* aFileInPage = [directoryContents objectAtIndex:filesSoFar];
                if([zip addFileToZip:[pathOfPageFiles stringByAppendingPathComponent:aFileInPage]
                         toPathInZip:aFileInPage]){
                }else{
                    NSLog(@"error for path: %@", aFileInPage);
                }
                CGFloat percentSoFar = ((CGFloat)filesSoFar / ([directoryContents count] + [bundledContents count]));
                [self.delegate isExportingPage:self withPercentage:percentSoFar toZipLocation:fullPathToZip];
            }
            for(int filesSoFar=0;filesSoFar<[bundledContents count];filesSoFar++){
                NSString* aFileInPage = [bundledContents objectAtIndex:filesSoFar];
                if([zip addFileToZip:[[self bundledPagesPath] stringByAppendingPathComponent:aFileInPage]
                         toPathInZip:aFileInPage]){
                }else{
                    NSLog(@"error for path: %@", aFileInPage);
                }
                CGFloat percentSoFar = ((CGFloat)filesSoFar / ([directoryContents count] + [bundledContents count]));
                [self.delegate isExportingPage:self withPercentage:percentSoFar toZipLocation:fullPathToZip];
            }
            [zip closeZipFile];
        }
        
        if(![[NSFileManager defaultManager] fileExistsAtPath:fullPathToTempZip]){
            // file wasn't created
            return nil;
        }else{
            NSLog(@"success? file generated at %@", fullPathToTempZip);
            NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPathToTempZip error:nil];
            if (attribs) {
                NSLog(@"zip file is %@", [NSByteCountFormatter stringFromByteCount:[attribs fileSize] countStyle:NSByteCountFormatterCountStyleFile]);
            }
            
            
            NSLog(@"validating zip file");
            zip = [[ZipArchive alloc] init];
            [zip unzipOpenFile:fullPathToTempZip];
            NSArray* contents = [zip contentsOfZipFile];
            [zip unzipCloseFile];
            
            if([contents count] > 0 && [contents count] == [directoryContents count] + [bundledContents count]){
                NSLog(@"valid zip file, contents: %d", (int) [contents count]);
                [[NSFileManager defaultManager] moveItemAtPath:fullPathToTempZip toPath:fullPathToZip error:nil];
            }else{
                NSLog(@"invalid zip file: %@ vs %@", contents, directoryContents);
                [[NSFileManager defaultManager] removeItemAtPath:fullPathToTempZip error:nil];
                return nil;
            }
        }
    }else{
        NSLog(@"success? file already exists at %@", fullPathToZip);
        NSDictionary *attribs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPathToZip error:nil];
        if (attribs) {
            NSLog(@"zip file is %@", [NSByteCountFormatter stringFromByteCount:[attribs fileSize] countStyle:NSByteCountFormatterCountStyleFile]);
        }
        NSLog(@"validating...");
        ZipArchive* zip = [[ZipArchive alloc] init];
        if([zip unzipOpenFile:fullPathToZip]){
            NSLog(@"valid");
            [zip closeZipFile];
        }else{
            NSLog(@"invalid");
            [[NSFileManager defaultManager] removeItemAtPath:fullPathToZip error:nil];
            return nil;
        }
    }
    

    
    /*
    
    NSLog(@"contents of zip: %@", contents);
    
    
    
    NSLog(@"unzipping file");
    
    NSString* unzipTargetDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safeDir"];
    
    zip = [[ZipArchive alloc] init];
    [zip unzipOpenFile:fullPathToZip];
    [zip unzipFileTo:unzipTargetDirectory overWrite:YES];
    [zip unzipCloseFile];
    
    
    directoryContents = [[NSFileManager defaultManager] recursiveContentsOfDirectoryAtPath:unzipTargetDirectory filesOnly:YES];
    NSLog(@"unzipped: %@", directoryContents);
    */
    
    return fullPathToZip;
}


@end