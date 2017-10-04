#import "MediaPicker.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

#define CDV_PHOTO_PREFIX @"cdv_photo_"

#define PROGRESS_MEDIA_IMPORTING @"MEDIA_IMPORTING"
#define PROGRESS_MEDIA_IMPORTED @"MEDIA_IMPORTED"

@interface MediaPicker ()

@property (copy) NSString* callbackId;
@property (copy) NSDictionary* options;

@end

@implementation MediaPicker
@synthesize callbackId;
@synthesize options;

- (void) cleanUp:(CDVInvokedUrlCommand *)command
{
	NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe

	NSError* error;
	NSMutableArray* directories = [NSMutableArray array];
	[directories addObject:[self getStoragePath:true]];
	[directories addObject:[self getStoragePath:false]];

	for (NSString* directory in directories)
	{
		for (NSString *file in [fileMgr contentsOfDirectoryAtPath:directory error:&error])
		{
			bool success = [fileMgr removeItemAtPath:[directory stringByAppendingPathComponent:file] error:&error];

			if (!success)
				[NSException exceptionWithName:@"Unable to delete file" reason:@"Unable to delete file" userInfo:nil];
		}
	}

	self.callbackId = command.callbackId;
	[self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK] callbackId:self.callbackId];
}

- (void) didFinishImagesWithResult: (CDVPluginResult *)pluginResult
{
	[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
	self.callbackId = nil;
}

- (NSString*) getErrorMessage:(NSError *)error
{
	NSDictionary *userInfo = [error userInfo];

	if (userInfo == nil)
		return [error localizedDescription];

	NSError *underlyingError = [userInfo objectForKey:NSUnderlyingErrorKey];
	if (underlyingError == nil)
		return [error localizedDescription];

	return [self getErrorMessage: underlyingError];
}

- (void) getPictures:(CDVInvokedUrlCommand *)command
{
	self.callbackId = command.callbackId;
	self.options = [command.arguments objectAtIndex: 0];

	[self.commandDelegate runInBackground:^
	{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status)
		{
			switch (status)
			{
				case PHAuthorizationStatusAuthorized:
				{
					NSInteger maxImages = [self.options[@"maxImages"] integerValue];
					NSInteger minImages = [self.options[@"minImages"] integerValue];
					BOOL sharedAlbums = [self.options[@"sharedAlbums"] boolValue] ?: false;
					NSString *mediaType = (NSString *)self.options[@"mediaType"];

					// Create the an album controller and image picker
					QBImagePickerController *imagePicker = [[QBImagePickerController alloc] init];
					imagePicker.allowsMultipleSelection = (maxImages >= 2);
					imagePicker.showsNumberOfSelectedItems = YES;
					imagePicker.maximumNumberOfSelection = maxImages;
					imagePicker.minimumNumberOfSelection = minImages;

					NSMutableArray *collections = [imagePicker.assetCollectionSubtypes mutableCopy];
					if (sharedAlbums)
						[collections addObject:@(PHAssetCollectionSubtypeAlbumCloudShared)];

					if ([mediaType isEqualToString:@"image"])
					{
						imagePicker.mediaType = QBImagePickerMediaTypeImage;
						[collections removeObject:@(PHAssetCollectionSubtypeSmartAlbumVideos)];
					}
					else if ([mediaType isEqualToString:@"video"])
					{
						imagePicker.mediaType = QBImagePickerMediaTypeVideo;
					}
					else
					{
						imagePicker.mediaType = QBImagePickerMediaTypeAny;
					}

					imagePicker.assetCollectionSubtypes = collections;
					imagePicker.delegate = self;

					// Display the picker in the main thread.
					__weak MediaPicker* weakSelf = self;
					dispatch_async(dispatch_get_main_queue(), ^
					{
						[weakSelf.viewController presentViewController:imagePicker animated:YES completion:nil];
					});

					break;
				}

				case PHAuthorizationStatusRestricted:
				case PHAuthorizationStatusDenied:
				{
					CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Please give this app permission to access your photo library in your phone settings!"];
					[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
					break;
				}

				default:
					break;
			}
		}];
	}];
}

- (NSString*) getStoragePath:(BOOL)isTemporaryStorage
{
	NSString* docsPath;
	if (isTemporaryStorage)
	{
		docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
	}
	else
	{
		NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		docsPath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
	}

	docsPath = [NSString stringWithFormat:@"%@/mediapicker", docsPath];
	NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe

	[fileMgr createDirectoryAtPath:docsPath withIntermediateDirectories:true attributes:nil error:nil];

	return docsPath;
}

- (NSString*) getWritableFile:(NSString*)extension isTemporaryStorage:(BOOL)isTemporaryStorage
{
	NSString *docsPath = [self getStoragePath:isTemporaryStorage];
	NSFileManager* fileMgr = [[NSFileManager alloc] init]; // recommended by Apple (vs [NSFileManager defaultManager]) to be threadsafe

	// generate unique file name
	for (int i = 0; i <= 99999; i++)
	{
		NSString* filePath = [NSString stringWithFormat:@"%@/%@%05d.%@", docsPath, CDV_PHOTO_PREFIX, i++, extension];
		if(![fileMgr fileExistsAtPath:filePath])
			return filePath;
	}

	[NSException exceptionWithName:@"Unable to getWritableFile" reason:@"No reserved file names remaining" userInfo:nil];
	return nil;
}

- (void) onMediaImporting:(NSNumber*)count
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	[result setObject:count forKey:@"data"];
	[result setObject:PROGRESS_MEDIA_IMPORTING forKey:@"type"];

	CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
	[pluginResult setKeepCallbackAsBool:true];
	[self.commandDelegate sendPluginResult:pluginResult callbackId: self.callbackId];
}

- (void) onMediaImported:(NSString*)filePath
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	[result setObject:filePath forKey:@"data"];
	[result setObject:PROGRESS_MEDIA_IMPORTED forKey:@"type"];

	CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
	[pluginResult setKeepCallbackAsBool:true];
	[self.commandDelegate sendPluginResult:pluginResult callbackId: self.callbackId];
}

#pragma mark - QBImagePickerControllerDelegate
- (void) qb_imagePickerController:(QBImagePickerController *)imagePickerController didFinishPickingItems:(NSArray *)assets
{
	[self.commandDelegate runInBackground:^
	{
		NSLog(@"Selected assets:");
		NSLog(@"%@", assets);
		PHImageManager *manager = [PHImageManager defaultManager];

		BOOL isTemporaryStorage = [self.options[@"isTemporaryStorage"] boolValue] ?: true;

		__block NSMutableArray *resultStrings = [[NSMutableArray alloc] init];

		NSNumber *assetCount = [NSNumber numberWithInt: [assets count]];
		[self onMediaImporting:assetCount];

		PHImageRequestOptions *phImageRequestOptions = [[PHImageRequestOptions alloc] init];
		phImageRequestOptions.networkAccessAllowed = YES;
		phImageRequestOptions.synchronous = NO;
		phImageRequestOptions.version = PHImageRequestOptionsVersionOriginal;

		PHVideoRequestOptions *phVideoRequestOptions = [[PHVideoRequestOptions alloc] init];
		phVideoRequestOptions.networkAccessAllowed = YES;
		phVideoRequestOptions.version = PHVideoRequestOptionsVersionOriginal;

		for (PHAsset *asset in assets)
		{
			if (asset.mediaType == PHAssetMediaTypeImage)
			{
				[manager requestImageDataForAsset: asset options: phImageRequestOptions resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info)
				{
					if (imageData == nil)
					{
						NSError *nsError = info[PHImageErrorKey];
						NSString *error = [self getErrorMessage: nsError];

						CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
						[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
					}
					else
					{
						NSString *filePath = [self getWritableFile:@"jpg" isTemporaryStorage:isTemporaryStorage];
						NSURL *fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];

						[imageData writeToFile:filePath atomically:YES];
						[resultStrings addObject:[fileURL absoluteString]];

						if ([resultStrings count] == [assets count])
						{
							CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:resultStrings];
							[self didFinishImagesWithResult:pluginResult];
						}
					}
				}];
			}
			else if (asset.mediaType == PHAssetMediaTypeVideo)
			{
				dispatch_semaphore_t sem = dispatch_semaphore_create(0);
				[manager requestAVAssetForVideo:asset options:phVideoRequestOptions resultHandler:^(AVAsset *videoAsset, AVAudioMix *audioMix, NSDictionary *info)
				{
					if (videoAsset == nil)
					{
						NSError *nsError = info[PHImageErrorKey];
						NSString *error = [self getErrorMessage: nsError];

						CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
						[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
					}
					else if ([videoAsset isKindOfClass:[AVURLAsset class]])
					{
						NSURL *inputURL = [(AVURLAsset*)videoAsset URL];

						NSString *filePath = [self getWritableFile:@"mp4" isTemporaryStorage:isTemporaryStorage];
						NSURL *fileURL = [NSURL fileURLWithPath:filePath isDirectory:NO];

						NSError *error = nil;
						BOOL success = [[NSFileManager defaultManager] copyItemAtPath:[inputURL path] toPath:filePath error:&error];

						if (!success)
						{
							CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
							[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
						}
						else
						{
							[self onMediaImported:[fileURL absoluteString]];

							[resultStrings addObject:[fileURL absoluteString]];
							if ([resultStrings count] == [assets count])
							{
								CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:resultStrings];
								[self didFinishImagesWithResult:pluginResult];
							}
						}
					}

					dispatch_semaphore_signal(sem);
				}];
				dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
			}
			else
			{
				CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unhandled Asset Type."];
				[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
				self.callbackId = nil;
			}
		}
	}];

	__weak MediaPicker* weakSelf = self;
	[weakSelf.viewController dismissViewControllerAnimated:YES completion:NULL];
}

- (void) qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController
{
	CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"CANCELLED"];
	[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
	self.callbackId = nil;

	__weak MediaPicker* weakSelf = self;
	[weakSelf.viewController dismissViewControllerAnimated:YES completion:NULL];
}

- (void) requestPermission:(CDVInvokedUrlCommand *)command
{
	self.callbackId = command.callbackId;
	self.options = [command.arguments objectAtIndex: 0];

	[self.commandDelegate runInBackground:^
	{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status)
		{
			switch (status)
			{
				case PHAuthorizationStatusAuthorized:
				{
					CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
					[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
					break;
				}

				case PHAuthorizationStatusRestricted:
				case PHAuthorizationStatusDenied:
				{
					CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Please give this app permission to access your photo library in your phone settings!"];
					[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
					break;
				}

				default:
				{
					CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"requestAuthorization status is not implemented."];
					[self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
					break;
				}
			}
		}];
	}];
}
@end

