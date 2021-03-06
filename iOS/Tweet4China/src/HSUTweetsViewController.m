//
//  HSUTweetsViewController.m
//  Tweet4China
//
//  Created by Jason Hsu on 5/3/13.
//  Copyright (c) 2013 Jason Hsu <support@tuoxie.me>. All rights reserved.
//

#import "HSUTweetsViewController.h"
#import "HSUComposeViewController.h"
#import "HSUNavigationBarLight.h"
#import "HSUGalleryView.h"
#import "HSUMiniBrowser.h"
#import "HSUStatusViewController.h"
#import "HSUProfileViewController.h"
#import "HSUProfileDataSource.h"
#import "TTTAttributedLabel.h"
#import "NSDate+Additions.h"
#import "HSUStatusCell.h"

@interface HSUTweetsViewController ()

@property (nonatomic, weak) UIViewController *modelVC;

@end

@implementation HSUTweetsViewController

- (void)preprocessDataSourceForRender:(HSUBaseDataSource *)dataSource
{
    [dataSource addEventWithName:@"reply" target:self action:@selector(reply:) events:UIControlEventTouchUpInside];
    [dataSource addEventWithName:@"retweet" target:self action:@selector(retweet:) events:UIControlEventTouchUpInside];
    [dataSource addEventWithName:@"favorite" target:self action:@selector(favorite:) events:UIControlEventTouchUpInside];
    [dataSource addEventWithName:@"more" target:self action:@selector(more:) events:UIControlEventTouchUpInside];
    [dataSource addEventWithName:@"delete" target:self action:@selector(delete:) events:UIControlEventTouchUpInside];
    [dataSource addEventWithName:@"touchAvatar" target:self action:@selector(touchAvatar:) events:UIControlEventTouchUpInside];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    HSUTableCellData *data = [self.dataSource dataAtIndexPath:indexPath];
    if ([data.dataType isEqualToString:kDataType_DefaultStatus]) {
        HSUStatusViewController *statusVC = [[HSUStatusViewController alloc] initWithStatus:data.rawData];
        [self.navigationController pushViewController:statusVC animated:YES];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

#pragma mark - Common actions
- (void)reply:(HSUTableCellData *)cellData {
    NSDictionary *rawData = cellData.rawData;
    NSString *screen_name = rawData[@"user"][@"screen_name"];
    NSString *id_str = rawData[@"id_str"];
    
    HSUComposeViewController *composeVC = [[HSUComposeViewController alloc] init];
    composeVC.defaultText = S(@" @%@ ", screen_name);
    composeVC.inReplyToStatusId = id_str;
    UINavigationController *nav = [[UINavigationController alloc] initWithNavigationBarClass:[HSUNavigationBarLight class] toolbarClass:nil];
    nav.viewControllers = @[composeVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)retweet:(HSUTableCellData *)cellData {
    NSDictionary *rawData = cellData.rawData;
    NSString *id_str = rawData[@"id_str"];
    
    [TWENGINE sendRetweetWithStatusID:id_str success:^(id responseObj) {
        NSMutableDictionary *newRawData = [rawData mutableCopy];
        newRawData[@"retweeted"] = @(YES);
        cellData.rawData = newRawData;
        [self.dataSource saveCache];
        notification_post(kNotification_HSUStatusCell_OtherCellSwiped);
        [self.tableView reloadData];
    } failure:^(NSError *error) {
        notification_post(kNotification_HSUStatusCell_OtherCellSwiped);
        [TWENGINE dealWithError:error errTitle:@"Retweet failed"];
    }];
}

- (void)favorite:(HSUTableCellData *)cellData {
    NSDictionary *rawData = cellData.rawData;
    NSString *id_str = rawData[@"id_str"];
    BOOL favorited = [rawData[@"favorited"] boolValue];
    
    if (favorited) {
        [TWENGINE unMarkStatus:id_str success:^(id responseObj) {
            NSMutableDictionary *newRawData = [rawData mutableCopy];
            newRawData[@"favorited"] = [NSNumber numberWithBool:!favorited];
            cellData.rawData = newRawData;
            [self.dataSource saveCache];
            [self.tableView reloadData];
        } failure:^(NSError *error) {
            [TWENGINE dealWithError:error errTitle:@"Favorite tweet failed"];
        }];
    } else {
        [TWENGINE markStatus:id_str success:^(id responseObj) {
            NSMutableDictionary *newRawData = [rawData mutableCopy];
            newRawData[@"favorited"] = [NSNumber numberWithBool:!favorited];
            cellData.rawData = newRawData;
            [self.dataSource saveCache];
            [self.tableView reloadData];
        } failure:^(NSError *error) {
            [TWENGINE dealWithError:error errTitle:@"Favorite tweet failed"];
        }];
    }
}

- (void)delete:(HSUTableCellData *)cellData
{
    RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
    cancelItem.action = ^{
        [self.tableView reloadData];
    };
    RIButtonItem *deleteItem = [RIButtonItem itemWithLabel:@"Delete Tweet"];
    deleteItem.action = ^{
        NSDictionary *rawData = cellData.rawData;
        NSString *id_str = rawData[@"id_str"];
        
        [TWENGINE destroyStatus:id_str success:^(id responseObj) {
            [self.dataSource removeCellData:cellData];
            [self.dataSource saveCache];
            [self.tableView reloadData];
        } failure:^(NSError *error) {
            [TWENGINE dealWithError:error errTitle:@"Delete tweet failed"];
        }];
    };
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:cancelItem destructiveButtonItem:deleteItem otherButtonItems:nil, nil];
    [actionSheet showInView:self.view.window];
}

- (void)more:(HSUTableCellData *)cellData {
    NSDictionary *rawData = cellData.rawData;
    
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:nil destructiveButtonItem:nil otherButtonItems:nil];
    uint count = 0;
    
    NSArray *urls = rawData[@"entities"][@"urls"];
    NSArray *medias = rawData[@"entities"][@"media"];
    if (medias && medias.count) {
        urls = [urls arrayByAddingObjectsFromArray:medias];
    }
    
    if (urls && urls.count) { // has link
        RIButtonItem *tweetLinkItem = [RIButtonItem itemWithLabel:@"Tweet link"];
        tweetLinkItem.action = ^{
            if (urls.count == 1) {
                NSString *link = [urls objectAtIndex:0][@"expanded_url"];
                [self _composeWithText:S(@" %@", link)];
            } else {
                UIActionSheet *selectLinkActionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:nil destructiveButtonItem:nil otherButtonItems:nil, nil];
                for (NSDictionary *urlDict in urls) {
                    NSString *displayUrl = urlDict[@"display_url"];
                    NSString *expendedUrl = urlDict[@"expanded_url"];
                    RIButtonItem *buttonItem = [RIButtonItem itemWithLabel:displayUrl];
                    buttonItem.action = ^{
                        [self _composeWithText:S(@" %@", expendedUrl)];
                    };
                    [selectLinkActionSheet addButtonItem:buttonItem];
                }
                
                RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
                [selectLinkActionSheet addButtonItem:cancelItem];
                
                [selectLinkActionSheet setCancelButtonIndex:urls.count];
                [selectLinkActionSheet showInView:self.view.window];
            }
        };
        [actionSheet addButtonItem:tweetLinkItem];
        count ++;
        
        RIButtonItem *copyLinkItem = [RIButtonItem itemWithLabel:@"Copy link"];
        copyLinkItem.action = ^{
            if (urls.count == 1) {
                NSString *link = [urls objectAtIndex:0][@"expanded_url"];
                UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                pasteboard.string = link;
            } else {
                UIActionSheet *selectLinkActionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:nil destructiveButtonItem:nil otherButtonItems:nil, nil];
                for (NSDictionary *urlDict in urls) {
                    NSString *displayUrl = urlDict[@"display_url"];
                    NSString *expendedUrl = urlDict[@"expanded_url"];
                    RIButtonItem *buttonItem = [RIButtonItem itemWithLabel:displayUrl];
                    buttonItem.action = ^{
                        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                        pasteboard.string = expendedUrl;
                    };
                    [selectLinkActionSheet addButtonItem:buttonItem];
                }
                
                RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
                [selectLinkActionSheet addButtonItem:cancelItem];
                
                [selectLinkActionSheet setCancelButtonIndex:urls.count];
                [selectLinkActionSheet showInView:self.view.window];
            }
        };
        [actionSheet addButtonItem:copyLinkItem];
        count ++;
        
        RIButtonItem *mailLinkItem = [RIButtonItem itemWithLabel:@"Mail link"];
        mailLinkItem.action = ^{
            if (urls.count == 1) {
                NSString *link = [urls objectAtIndex:0][@"expanded_url"];
                NSString *subject = @"Link from Twitter";
                NSString *body = S(@"<a href=\"%@\">%@</a>", link, link);
                [HSUCommonTools sendMailWithSubject:subject body:body presentFromViewController:self];
            } else {
                UIActionSheet *selectLinkActionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:nil destructiveButtonItem:nil otherButtonItems:nil, nil];
                for (NSDictionary *urlDict in urls) {
                    NSString *displayUrl = urlDict[@"display_url"];
                    NSString *expendedUrl = urlDict[@"expanded_url"];
                    RIButtonItem *buttonItem = [RIButtonItem itemWithLabel:displayUrl];
                    buttonItem.action = ^{
                        NSString *subject = @"Link from Twitter";
                        NSString *body = S(@"<a href=\"%@\">%@</a>", expendedUrl, displayUrl);
                        [HSUCommonTools sendMailWithSubject:subject body:body presentFromViewController:self];
                    };
                    [selectLinkActionSheet addButtonItem:buttonItem];
                }
                
                RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
                [selectLinkActionSheet addButtonItem:cancelItem];
                
                [selectLinkActionSheet setCancelButtonIndex:urls.count];
                [selectLinkActionSheet showInView:self.view.window];
            }
        };
        [actionSheet addButtonItem:mailLinkItem];
        count ++;
    }
    
    NSString *id_str = rawData[@"id_str"];
    NSString *link = S(@"https://twitter.com/rtfocus/status/%@", id_str);
    
    RIButtonItem *copyLinkToTweetItem = [RIButtonItem itemWithLabel:@"Copy link to Tweet"];
    copyLinkToTweetItem.action = ^{
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = link;
    };
    [actionSheet addButtonItem:copyLinkToTweetItem];
    count ++;
    
    NSString *name = rawData[@"user"][@"name"];
    NSString *screen_name = rawData[@"user"][@"screen_name"];
    NSString *profile_image_url_https = rawData[@"user"][@"profile_image_url_https"];
    NSString *text = rawData[@"text"];
    NSDate *createTime = [TWENGINE getDateFromTwitterCreatedAt:rawData[@"created_at"]];
    NSString *create_time = createTime.standardTwitterDisplay;
    
    RIButtonItem *mailTweetItem = [RIButtonItem itemWithLabel:@"Mail Tweet"];
    mailTweetItem.action = ^{
        NSURL *templatFileURL = [[NSBundle mainBundle] URLForResource:@"mail_tweet_template" withExtension:@"html"];
        // TODO: replace template placeholders with contents
        NSString *body = [[NSString alloc] initWithContentsOfURL:templatFileURL encoding:NSUTF8StringEncoding error:nil];;
        body = [body stringByReplacingOccurrencesOfString:@"${profile_image_url_https}" withString:profile_image_url_https];
        body = [body stringByReplacingOccurrencesOfString:@"${name}" withString:name];
        body = [body stringByReplacingOccurrencesOfString:@"${screen_name}" withString:screen_name];
        body = [body stringByReplacingOccurrencesOfString:@"${id_str}" withString:id_str];
        body = [body stringByReplacingOccurrencesOfString:@"${create_time}" withString:create_time];
        body = [body stringByReplacingOccurrencesOfString:@"${html}" withString:text];
        NSString *subject = @"Link from Twitter";
        [HSUCommonTools sendMailWithSubject:subject body:body presentFromViewController:self];
    };
    [actionSheet addButtonItem:mailTweetItem];
    count ++;
    
    RIButtonItem *RTItem = [RIButtonItem itemWithLabel:@"RT"];
    RTItem.action = ^{
        HSUComposeViewController *composeVC = [[HSUComposeViewController alloc] init];
        NSDictionary *rawData = [self.dataSource dataAtIndex:0].rawData;
        NSString *authorScreenName = rawData[@"user"][@"screen_name"];
        NSString *text = rawData[@"text"];
        composeVC.defaultText = S(@" RT @%@: %@", authorScreenName, text);
        UINavigationController *nav = [[UINavigationController alloc] initWithNavigationBarClass:[HSUNavigationBarLight class] toolbarClass:nil];
        nav.viewControllers = @[composeVC];
        [self presentViewController:nav animated:YES completion:nil];
    };
    [actionSheet addButtonItem:RTItem];
    count ++;
    
    RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
    [actionSheet addButtonItem:cancelItem];
    
    [actionSheet setCancelButtonIndex:count];
    [actionSheet showInView:[UIApplication sharedApplication].keyWindow];
}

- (void)touchAvatar:(HSUTableCellData *)cellData
{
    NSString *screenName = cellData.rawData[@"retweeted_status"][@"user"][@"screen_name"] ?: cellData.rawData[@"user"][@"screen_name"];
    HSUProfileViewController *profileVC = [[HSUProfileViewController alloc] initWithScreenName:screenName];
    profileVC.profile = cellData.rawData[@"retweeted_status"][@"user"] ?: cellData.rawData[@"user"];
    [self.navigationController pushViewController:profileVC animated:YES];
}

- (void)_composeWithText:(NSString *)text
{
    HSUComposeViewController *composeVC = [[HSUComposeViewController alloc] init];
    composeVC.defaultText = text;
    UINavigationController *nav = [[UINavigationController alloc] initWithNavigationBarClass:[HSUNavigationBarLight class] toolbarClass:nil];
    nav.viewControllers = @[composeVC];
    [self.modelVC ?: self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - attributtedLabel delegate
- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithArguments:(NSDictionary *)arguments
{
    // User Link
    NSURL *url = [arguments objectForKey:@"url"];
    //    HSUTableCellData *cellData = [arguments objectForKey:@"cell_data"];
    if ([url.absoluteString hasPrefix:@"user://"] ||
        [url.absoluteString hasPrefix:@"tag://"]) {
        RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
        RIButtonItem *copyItem = [RIButtonItem itemWithLabel:@"Copy Content"];
        copyItem.action = ^{
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            pasteboard.string = label.text;
        };
        UIActionSheet *linkActionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:cancelItem destructiveButtonItem:nil otherButtonItems:copyItem, nil];
        [linkActionSheet showInView:self.view.window];
        return;
    }
    
    // Commen Link
    RIButtonItem *cancelItem = [RIButtonItem itemWithLabel:@"Cancel"];
    RIButtonItem *tweetLinkItem = [RIButtonItem itemWithLabel:@"Tweet Link"];
    tweetLinkItem.action = ^{
        [self _composeWithText:S(@" %@", url.absoluteString)];
    };
    RIButtonItem *copyLinkItem = [RIButtonItem itemWithLabel:@"Copy Link"];
    copyLinkItem.action = ^{
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = url.absoluteString;
    };
    RIButtonItem *mailLinkItem = [RIButtonItem itemWithLabel:@"Mail Link"];
    mailLinkItem.action = ^{
        NSString *body = S(@"<a href=\"%@\">%@</a><br><br>", url.absoluteString, url.absoluteString);
        NSString *subject = @"Link from Twitter";
        [HSUCommonTools sendMailWithSubject:subject body:body presentFromViewController:self];
    };
    RIButtonItem *openInSafariItem = [RIButtonItem itemWithLabel:@"Open in Safari"];
    openInSafariItem.action = ^{
        [[UIApplication sharedApplication] openURL:url];
    };
    UIActionSheet *linkActionSheet = [[UIActionSheet alloc] initWithTitle:nil cancelButtonItem:cancelItem destructiveButtonItem:nil otherButtonItems:tweetLinkItem, copyLinkItem, mailLinkItem, openInSafariItem, nil];
    [linkActionSheet showInView:self.view.window];
}

- (void)attributedLabel:(TTTAttributedLabel *)label didReleaseLinkWithArguments:(NSDictionary *)arguments
{
    NSURL *url = [arguments objectForKey:@"url"];
    HSUTableCellData *cellData = [arguments objectForKey:@"cell_data"];
    if ([url.absoluteString hasPrefix:@"user://"]) {
        NSString *screenName = [url.absoluteString substringFromIndex:7];
        HSUProfileViewController *profileVC = [[HSUProfileViewController alloc] initWithScreenName:screenName];
        [self.navigationController pushViewController:profileVC animated:YES];
        return;
    }
    if ([url.absoluteString hasPrefix:@"tag://"]) {
        // Push Tag ViewController
        return;
    }
    NSString *attr = cellData.renderData[@"attr"];
    if ([attr isEqualToString:@"photo"]) {
        if ([url.absoluteString hasPrefix:@"http://instagram.com"] || [url.absoluteString hasPrefix:@"http://instagr.am"]) {
            NSString *imageUrl = cellData.renderData[@"photo_url"];
            if (imageUrl) {
                [self openPhotoURL:[NSURL URLWithString:imageUrl] withCellData:cellData];
                return;
            }
        }
        NSString *mediaURLHttps;
        NSArray *medias = cellData.rawData[@"entities"][@"media"];
        for (NSDictionary *media in medias) {
            NSString *expandedUrl = media[@"expanded_url"];
            if ([expandedUrl isEqualToString:url.absoluteString]) {
                mediaURLHttps = media[@"media_url_https"];
            }
        }
        if (mediaURLHttps) {
            [self openPhotoURL:[NSURL URLWithString:mediaURLHttps] withCellData:cellData];
            return;
        }
    }
    [self openWebURL:url withCellData:cellData];
}

- (void)openPhotoURL:(NSURL *)photoURL withCellData:(HSUTableCellData *)cellData
{
    HSUGalleryView *galleryView = [[HSUGalleryView alloc] initWithData:cellData imageURL:photoURL];
    galleryView.viewController = self;
    [self.view.window addSubview:galleryView];
    [galleryView showWithAnimation:YES];
}

- (void)openWebURL:(NSURL *)webURL withCellData:(HSUTableCellData *)cellData
{
    UINavigationController *nav = [[UINavigationController alloc] initWithNavigationBarClass:[HSUNavigationBarLight class] toolbarClass:nil];
    HSUMiniBrowser *miniBrowser = [[HSUMiniBrowser alloc] initWithURL:webURL cellData:cellData];
    miniBrowser.viewController = self;
    nav.viewControllers = @[miniBrowser];
    [self presentViewController:nav animated:YES completion:nil];
    self.modelVC = miniBrowser;
}

@end
