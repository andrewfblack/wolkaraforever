#import "Installation.h"
#import "Manifest.h"
#import "ExternalGameRecord.h"

@implementation TKWoWInstallation
@end

// .build.info tags are space-delimited. Match a complete token: `deDE` must
// not become a match merely because it occurs inside another tag.
static BOOL TKWoWTagsContainLocale(NSString *tags, NSString *locale) {
    if (![tags isKindOfClass:NSString.class] || ![locale isKindOfClass:NSString.class] || !locale.length) return NO;
    for (NSString *tag in [tags componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
        if ([tag isEqual:locale]) return YES;
    return NO;
}

TKWoWInstallation *TKWoWInspectInstallation(TKAppLibrary *library, NSDictionary *product, NSDictionary *plan) {
    TKWoWInstallation *result=[TKWoWInstallation new];
    result.state=TKWoWInstallationMissing;
    for (TKApp *app in library.apps) {
        if (app.source!=TKAppSourceDocuments || ![app.workingDirectory.lastPathComponent isEqual:product[@"folder"]]) continue;
        result.state=TKWoWInstallationNeedsRepair; result.app=app;
        NSError *error=nil;
        NSString *directory=[library workingDirectoryForApp:app error:&error];
        NSString *path=[library executablePathForApp:app error:&error];
        if (!directory || !path) { result.error=error; return result; }
        NSString *info=[directory.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".build.info"];
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:info error:&error];
        if (!attributes || [attributes[NSFileSize] unsignedLongLongValue]>2*1024*1024) {
            result.error=error?:TKWoWError(@"Missing or oversized installation metadata."); return result;
        }
        NSData *data=[NSData dataWithContentsOfFile:info options:0 error:&error];
        NSArray *rows=data?TKWoWTable(data,&error):nil;
        if (!rows) { result.error=error; return result; }
        NSDictionary *match=nil;
        for (NSDictionary *row in rows) if ([row[@"Product"] isEqual:product[@"id"]] && [row[@"Active"] isEqual:@"1"]) {
            if (match) { result.error=TKWoWError(@"Ambiguous installed build."); return result; }
            match=row;
        }
        if (!match || !TKWoWHashValid(match[@"Build Key"]) || !TKWoWHashValid(match[@"CDN Key"]) || ![match[@"Version"] length]) {
            result.error=TKWoWError(@"No valid installed build metadata."); return result;
        }
        result.installedVersion=match[@"Version"];
        if (!TKWoWBuildCurrent(rows,product[@"id"],plan[@"version"])) {
            result.state=TKWoWInstallationOutdated; return result;
        }
        if (!TKWoWTagsContainLocale(match[@"Tags"],plan[@"locale"])) {
            result.state=TKWoWInstallationOutdated;
            result.localeNeedsUpdate=YES;
            return result;
        }
        NSString *prefix=[directory stringByAppendingString:@"/"];
        if (![path hasPrefix:prefix]) { result.error=TKWoWError(@"Executable is outside the edition folder."); return result; }
        NSString *relative=[path substringFromIndex:prefix.length];
        for (NSDictionary *file in plan[@"files"]) if ([file[@"path"] isEqual:relative]) {
            attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:&error];
            uint64_t size=[attributes[NSFileSize] unsignedLongLongValue];
            if (!attributes || size>256*1024*1024 || size!=[file[@"size"] unsignedLongLongValue]) break;
            NSData *original=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
            if (original && [TKWoWMD5(original) isEqual:file[@"contentKey"]]) {
                result.state=TKWoWInstallationReady; result.app=app; return result;
            }
            break;
        }
        result.error=error?:TKWoWError(@"The original executable does not match the published build.");
        return result;
    }
    return result;
}

// External Forever installation: read-only. An absent card is NeedsRepair with
// a reason, never Missing, so no fresh internal download is offered for it.
TKWoWInstallation *TKWoWInspectExternalInstallation(NSDictionary *product, NSDictionary *plan) {
    TKWoWInstallation *result=[TKWoWInstallation new];
    result.state=TKWoWInstallationNeedsRepair;
    if (![product[@"id"] isEqual:@"wowf"] || ![TKExternalGameRecord hasRecord]) {
        result.error=TKWoWError(@"No external Forever installation is registered."); return result;
    }
    NSError *error=nil;
    NSURL *folder=[TKExternalGameRecord beginInstallAccess:&error];
    if (!folder) { result.error=error; return result; }
    @try {
        NSString *root=[TKExternalGameRecord gameRootInFolder:folder.path error:&error];
        if (!root) { result.error=error; return result; }
        NSString *info=[root stringByAppendingPathComponent:@".build.info"];
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:info error:NULL];
        if (!attributes) {
            // No metadata yet: the external install has not completed its first
            // activation. Missing is safe because the caller routes Install to
            // this same record rather than to internal storage.
            result.state=TKWoWInstallationMissing; return result;
        }
        if ([attributes[NSFileSize] unsignedLongLongValue]>2*1024*1024) {
            result.error=TKWoWError(@"Missing or oversized external installation metadata."); return result;
        }
        NSData *data=[NSData dataWithContentsOfFile:info options:0 error:&error];
        NSArray *rows=data?TKWoWTable(data,&error):nil;
        if (!rows) { result.error=error?:TKWoWError(@"External installation metadata is invalid."); return result; }
        NSDictionary *match=nil;
        for (NSDictionary *row in rows) if ([row[@"Product"] isEqual:product[@"id"]] && [row[@"Active"] isEqual:@"1"]) {
            if (match) { result.error=TKWoWError(@"Ambiguous external installation metadata."); return result; }
            match=row;
        }
        if (!match || !TKWoWHashValid(match[@"Build Key"]) || !TKWoWHashValid(match[@"CDN Key"]) || ![match[@"Version"] length]) {
            result.error=TKWoWError(@"No valid external installation metadata."); return result;
        }
        result.installedVersion=match[@"Version"];
        if (!TKWoWBuildCurrent(rows,product[@"id"],plan[@"version"])) {
            result.state=TKWoWInstallationOutdated; return result;
        }
        if (!TKWoWTagsContainLocale(match[@"Tags"],plan[@"locale"])) {
            result.state=TKWoWInstallationOutdated; result.localeNeedsUpdate=YES; return result;
        }
        NSString *relative=[TKExternalGameRecord recordedExecutable];
        if (!relative) {
            // A completed download whose record was interrupted before attach:
            // only the plan's own executable, verified by content, may be used.
            for (NSDictionary *file in plan[@"files"]) {
                NSString *path=file[@"path"];
                if (![path hasSuffix:@".app/Contents/MacOS/World of Warcraft"]) continue;
                NSString *candidate=[root stringByAppendingPathComponent:path];
                NSDictionary *executableAttributes=[NSFileManager.defaultManager attributesOfItemAtPath:candidate error:NULL];
                if ([executableAttributes[NSFileSize] unsignedLongLongValue]!=[file[@"size"] unsignedLongLongValue]) continue;
                NSData *bytes=[NSData dataWithContentsOfFile:candidate options:NSDataReadingMappedIfSafe error:NULL];
                if (bytes && [TKWoWMD5(bytes) isEqual:file[@"contentKey"]]) { relative=path; break; }
            }
            if (!relative) {
                result.error=TKWoWError(@"The external executable is unavailable or does not match the published build.");
                return result;
            }
            if (![TKExternalGameRecord attachExecutable:relative inFolder:folder error:&error]) {
                result.error=error; return result;
            }
        }
        NSDictionary *paths=[TKExternalGameRecord validatedPathsWithFolder:folder error:&error];
        if (!paths) { result.error=error; return result; }
        NSString *executable=paths[@"executable"];
        for (NSDictionary *file in plan[@"files"]) if ([file[@"path"] isEqual:relative]) {
            NSData *bytes=[NSData dataWithContentsOfFile:executable options:NSDataReadingMappedIfSafe error:&error];
            if (bytes.length==[file[@"size"] unsignedLongLongValue] && [TKWoWMD5(bytes) isEqual:file[@"contentKey"]]) {
                result.state=TKWoWInstallationReady; return result;
            }
            break;
        }
        result.error=error?:TKWoWError(@"The external executable does not match the published build.");
        return result;
    } @finally {
        [TKExternalGameRecord endAccess:folder];
    }
}
