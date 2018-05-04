class Popularity
  SORT_ASCENDING = 1
  SORT_DESCENDING = -1

  def self.most_popular(limit)
    sort_by_popularity(SORT_DESCENDING, limit)
  end

  def self.least_popular(limit)
    sort_by_popularity(SORT_ASCENDING, limit)
  end

  def self.sort_by_popularity(sort_direction, limit)
    MongoClient[:popularity].aggregate([
      { "$sort" => { timestamp: -1 } },
      { "$group" => { _id: "$instrument_id", latest_popularity: { "$first" => "$popularity" } } },
      { "$lookup" => {
        from: "index",
        localField: "_id",
        foreignField: "instrument_id",
        as: "indexes",
      } },
      { "$sort" => { latest_popularity: sort_direction } },
      { "$limit" => limit },
    ])
  end

  def self.get_history_for_symbol(symbol)
    entry = MongoClient[:index].aggregate([
      { "$match" => { symbol: symbol } },
      { "$lookup" => {
        from: "popularity",
        localField: "instrument_id",
        foreignField: "instrument_id",
        as: "popularity_history",
      } },
      { "$limit" => 1 },
    ]).first
    entry && entry["popularity_history"]
  end

  def self.largest_popularity_changes(options)
    options = options.merge(sort_direction: SORT_DESCENDING, take_absoute_value: true)
    popularity_difference_lookup(options)
  end

  def self.largest_popularity_decreases(options)
    popularity_difference_lookup(options.merge(sort_direction: SORT_ASCENDING))
  end

  def self.largest_popularity_increases(options)
    popularity_difference_lookup(options.merge(sort_direction: SORT_DESCENDING))
  end

  def self.popularity_difference_lookup(options)
    hours_ago          = options[:hours_ago]
    sort_direction     = options[:sort_direction]
    limit              = options[:limit]
    take_absoute_value = options[:take_absoute_value]
    percentage         = options[:percentage]
    min_popularity     = options[:min_popularity]

    if percentage
      difference_query = { "$multiply" => [100, { "$divide" => [{ "$subtract" => ["$end_popularity", "$start_popularity"] }, "$start_popularity"] }] }
    else
      difference_query = { "$subtract" => ["$end_popularity", "$start_popularity"] }
    end

    if take_absoute_value
      sorter = { "$sort" => { abs_popularity_difference: sort_direction } }
    else
      sorter = { "$sort" => { popularity_difference: sort_direction } }
    end

    MongoClient[:popularity].aggregate([
      { "$match" => { timestamp: { "$gte" => hours_ago.hour.ago.utc } } },
      { "$sort" => { timestamp: -1 } },
      { "$group" => {
        _id: "$instrument_id",
        end_popularity: { "$first" => "$popularity" },
        start_popularity: { "$last" => "$popularity" },
      } },
      { "$lookup" => {
        from: "index",
        localField: "_id",
        foreignField: "instrument_id",
        as: "indexes",
      } },
      { "$addFields" => { popularity_difference: difference_query } },
      min_popularity && { "$match" => { start_popularity: { "$gte" => min_popularity } } },
      take_absoute_value && { "$addFields" => { abs_popularity_difference: { "$abs" => "$popularity_difference" } } },
      sorter,
      { "$limit" => limit },
    ].compact)
  end
end
