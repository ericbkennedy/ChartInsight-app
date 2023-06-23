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

/// FundamentalFetcher calls StockData with the columns parsed out of the API
- (void) fetcherLoadedFundamentals:(NSDictionary<NSString*, NSArray<NSDecimalNumber*>*>*)columns;

/// DataFetcher calls StockData with the array of historical price data
- (void) fetcherLoadedHistoricalData:(NSArray<BarData*> *)loadedData;

/// DataFetcher calls StockData with intraday price data
- (void) fetcherLoadedIntradayBar:(BarData *)intradayBar;

/// DataFetcher failed downloading historical data or intraday data
- (void) fetcherFailed:(NSString *)message;

/// DataFetcher has an active download that must be allowed to finish or fail before accepting an additional request
- (void) fetcherCanceled;

@end

#endif /* DataFetcherDelegate_h */
