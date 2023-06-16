//
//  DataFetcherDelegate.h
//  ChartInsight
//
//  StockData accepts these delegate method calls from DataFetcher.swift
//
//  Created by Eric Kennedy on 6/15/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

#ifndef DataFetcherDelegate_h
#define DataFetcherDelegate_h

@class BarData;

@protocol DataFetcherDelegate

- (void) fetcherLoadedHistoricalData:(NSArray<BarData*> *)loadedData;

- (void) fetcherLoadedIntradayBar:(BarData *)intradayBar;

- (void) fetcherFailed:(NSString *)message;

- (void) fetcherCanceled;

@end

#endif /* DataFetcherDelegate_h */
