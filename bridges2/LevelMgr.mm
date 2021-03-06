/*******************************************************************************
 *
 * Copyright 2012 Zack Grossbart
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 ******************************************************************************/

#import "LevelMgr.h"
#import "JSONKit.h"
#import "cocos2d.h"
#import "GLES-Render.h"
#import "LayerMgr.h"
#import "ScreenShotLayer.h"
#import "BridgeColors.h"
#import "UIImageExtras.h"

#define PTM_RATIO 32.0

@interface LevelMgr()
@property (readwrite, retain) NSMutableDictionary *levels;
@property (readwrite,copy) NSArray *levelIds;
@property (readwrite) CCGLView *glView;
@end

@implementation LevelMgr

+ (LevelMgr*)getLevelMgr {
    static LevelMgr *levelMgr;
    
    @synchronized(self)
    {
        if (!levelMgr) {
            levelMgr = [[LevelMgr alloc] init];
            levelMgr.levels = [NSMutableDictionary dictionaryWithCapacity:25];
            
            [levelMgr loadLevels];
        }
        
        return levelMgr;
    }
}

-(void)loadLevels {
    NSString *path = [[NSBundle mainBundle] bundlePath];
    
    NSError *error;
    NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    
    for (NSString *file in directoryContents) {
        if ([file hasPrefix:@"level"] &&
            [file hasSuffix:@".json"]) {
            NSString *jsonString = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:nil];
            NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:[path stringByAppendingPathComponent:file] error:&error];
            NSDate *fileDate =[dictionary objectForKey:NSFileModificationDate];
            
            Level *level = [[Level alloc] initWithJson:jsonString: fileDate];
            [self.levels setObject:level forKey:level.levelId];
        }
    }
    
    self.levelIds = [self sortLevels];
    
    //    NSLog(@"levels ====== %@",self.levels);
}

-(NSArray *)sortLevels {
    return [[self.levels allKeys] sortedArrayUsingComparator:(NSComparator)^(id obj1, id obj2){
        int i1 = [obj1 integerValue];
        int i2 = [obj2 integerValue];
        if (i1 > i2) {
            return NSOrderedDescending;
        } else if (i1 < i2) {
            return NSOrderedAscending;
        } else {
            return NSOrderedSame;
        }
    }];
}

-(void)setupCocos2D: (CGRect) bounds {
    if (_hasInit) {
        return;
    }
    
    CCGLView *glView = [CCGLView viewWithFrame:bounds
								   pixelFormat:kEAGLColorFormatRGB565	//kEAGLColorFormatRGBA8
								   depthFormat:0	//GL_DEPTH_COMPONENT24_OES
							preserveBackbuffer:NO
									sharegroup:nil
								 multiSampling:NO
							   numberOfSamples:0];
    glView_ = glView;
    self.glView = glView_;
    
	// Enable multiple touches
	[glView setMultipleTouchEnabled:YES];
    
	director_ = (CCDirectorIOS*) [CCDirector sharedDirector];
	
	director_.wantsFullScreenLayout = YES;
	
	[director_ setDisplayStats:NO];
	
	// set FPS at 60
	[director_ setAnimationInterval:1.0/60];
	
	// attach the openglView to the director
	[director_ setView:glView];
	
	// for rotation and other messages
	//[director_ setDelegate:self];
	
	// 2D projection
	[director_ setProjection:kCCDirectorProjection2D];
	//	[director setProjection:kCCDirectorProjection3D];
	
	// Enables High Res mode (Retina Display) on iPhone 4 and maintains low res on all other devices
	if( ! [director_ enableRetinaDisplay:YES] )
		CCLOG(@"Retina Display Not supported");
	
	// Default texture format for PNG/BMP/TIFF/JPEG/GIF images
	// It can be RGBA8888, RGBA4444, RGB5_A1, RGB565
	// You can change anytime.
	[CCTexture2D setDefaultAlphaPixelFormat:kCCTexture2DPixelFormat_RGBA8888];
	
	// If the 1st suffix is not found and if fallback is enabled then fallback suffixes are going to searched. If none is found, it will try with the name without suffix.
	// On iPad HD  : "-ipadhd", "-ipad",  "-hd"
	// On iPad     : "-ipad", "-hd"
	// On iPhone HD: "-hd"
	CCFileUtils *sharedFileUtils = [CCFileUtils sharedFileUtils];
	[sharedFileUtils setEnableFallbackSuffixes:NO];				// Default: NO. No fallback suffixes are going to be used
	[sharedFileUtils setiPhoneRetinaDisplaySuffix:@"-hd"];		// Default on iPhone RetinaDisplay is "-hd"
	[sharedFileUtils setiPadSuffix:@"-ipad"];					// Default on iPad is "ipad"
	[sharedFileUtils setiPadRetinaDisplaySuffix:@"-hd"];	// Default on iPad RetinaDisplay is "-ipadhd"
	
	// Assume that PVR images have premultiplied alpha
	[CCTexture2D PVRImagesHavePremultipliedAlpha:YES];
	
    _hasInit = true;
}

-(void)drawLevels:(CGRect) bounds {
    [self setupCocos2D:bounds];
    
    NSMutableArray *levels = [NSMutableArray arrayWithCapacity:20];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if([paths count] > 0) {
        for (NSString* levelId in self.levelIds) {
            Level *level = (Level*) [self.levels objectForKey:levelId];
            
            NSString *documentsDirectory = [paths objectAtIndex:0];
            
            NSString *path = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"level%@.png", level.levelId]];
            
            NSError *error;
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
                NSDate *fileDate =[dictionary objectForKey:NSFileModificationDate];
                
                if ([level.date compare:fileDate] == NSOrderedDescending) {
                    [levels addObject:level];
                } else {
                    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                    
                    dispatch_async(queue, ^{
                        level.screenshot = [UIImage imageWithContentsOfFile:path];
                    });
                }
            } else {
                [levels addObject:level];
            }
        }
    }
    
    if ([levels count] > 0) {
        /*
         * Then we have some levels that still need screenshots.  We'll draw
         * them in a different thread so we don't slow down the UI.
         */
        dispatch_async(dispatch_get_main_queue(), ^{
            [self doDrawLevels:bounds:levels];
        });
    }
}

-(void)doDrawLevels:(CGRect) bounds: (NSMutableArray*) levels {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);        
    
    b2Vec2 gravity = b2Vec2(0.0f, 0.0f);
    bool doSleep = false;
    b2World *world = new b2World(gravity);
    world->SetAllowSleeping(doSleep);
    
    [[CCSpriteFrameCache sharedSpriteFrameCache]
     addSpriteFramesWithFile:@"bridgesprites.plist"];
    
    // Create our sprite sheet and frame cache
    CCSpriteBatchNode *spriteSheet = [[CCSpriteBatchNode batchNodeWithFile:@"bridgesprites.pvr.gz"
                                                                  capacity:150] retain];
    
    LayerMgr *layerMgr = [[LayerMgr alloc] initWithSpriteSheet:spriteSheet:world];
    layerMgr.addBoxes = false;
    
    CCRenderTexture *renderer	= [CCRenderTexture renderTextureWithWidth:bounds.size.width height:bounds.size.height];
    
    ScreenShotLayer *scene = [[ScreenShotLayer alloc] init];
    
    [scene addChild:spriteSheet];
    
    CGSize s = CGSizeMake(96, 64);
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        s = CGSizeMake(216, 144);
    }
    
    for (Level* level in levels) {
        layerMgr.tileSize = CGSizeMake(bounds.size.height / level.tileCount, bounds.size.height / level.tileCount);
        
        NSString *documentsDirectory = [paths objectAtIndex:0];
        
        NSString *path = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"level%@.png", level.levelId]];
        
        [level addSprites:layerMgr:nil];
        
        [renderer begin];
        [scene visit];
        [renderer end];
        
        UIImage *image = [renderer getUIImage];
        [image imageByScalingAndCroppingForSize:s];
        [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        level.screenshot = image;
        
        [layerMgr removeAll];
        
    }
    
    delete world;
    world = nil;
    
    [spriteSheet release];
    [scene dealloc];
    
    [layerMgr release];
    
}

-(void)dealloc {
    
    [_levels release];
    _levels = nil;
    
    [_levelIds release];
    _levelIds = nil;
    
    [super dealloc];
    
}

@end
