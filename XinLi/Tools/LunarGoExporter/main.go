// ChronoCal's offline exporter. Upstream calendar algorithms and almanac data are
// supplied by github.com/6tail/lunar-go v1.4.6, under its retained MIT license.
package main

import (
	"container/list"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/6tail/lunar-go/calendar"
)

const schemaVersion = 1

type HourRecord struct {
	Branch               string   `json:"branch"`
	GanZhi               string   `json:"ganZhi"`
	TimeRange            string   `json:"timeRange"`
	HeavenlySpirit       string   `json:"heavenlySpirit"`
	Luck                 string   `json:"luck"`
	SuitableActivities   []string `json:"suitableActivities"`
	UnsuitableActivities []string `json:"unsuitableActivities"`
	Clash                string   `json:"clash"`
	Sha                  string   `json:"sha"`
}

type DayRecord struct {
	Date                 string       `json:"date"`
	LunarYear            int          `json:"lunarYear"`
	LunarMonth           int          `json:"lunarMonth"`
	LunarDay             int          `json:"lunarDay"`
	YearGanZhi           string       `json:"yearGanZhi"`
	MonthGanZhi          string       `json:"monthGanZhi"`
	DayGanZhi            string       `json:"dayGanZhi"`
	SuitableActivities   []string     `json:"suitableActivities"`
	UnsuitableActivities []string     `json:"unsuitableActivities"`
	Clashes              []string     `json:"clashes"`
	PengZu               []string     `json:"pengZu"`
	Hours                []HourRecord `json:"hours"`
}

type YearRecords struct {
	SchemaVersion int         `json:"schemaVersion"`
	Year          int         `json:"year"`
	Records       []DayRecord `json:"records"`
}

func stringsFromList(values *list.List) []string {
	result := make([]string, 0, values.Len())
	for item := values.Front(); item != nil; item = item.Next() {
		// Fail on an unexpected upstream type instead of silently dropping data.
		result = append(result, item.Value.(string))
	}
	return result
}

func exportDay(year int, month int, day int) DayRecord {
	solar := calendar.NewSolarFromYmd(year, month, day)
	lunar := solar.GetLunar()
	hours := make([]HourRecord, 0, 13)
	for _, hour := range lunar.GetTimes() {
		hours = append(hours, HourRecord{
			Branch: hour.GetZhi(), GanZhi: hour.GetGanZhi(),
			TimeRange:      hour.GetMinHm() + "–" + hour.GetMaxHm(),
			HeavenlySpirit: hour.GetTianShen(), Luck: hour.GetTianShenLuck(),
			SuitableActivities:   stringsFromList(hour.GetYi()),
			UnsuitableActivities: stringsFromList(hour.GetJi()),
			Clash:                "冲" + hour.GetChongDesc(), Sha: "煞" + hour.GetSha(),
		})
	}
	if len(hours) != 13 || hours[0].TimeRange != "00:00–00:59" || hours[12].TimeRange != "23:00–23:59" {
		panic("upstream hour segmentation changed")
	}
	return DayRecord{
		Date: solar.ToYmd(), LunarYear: lunar.GetYear(), LunarMonth: lunar.GetMonth(), LunarDay: lunar.GetDay(),
		YearGanZhi: lunar.GetYearInGanZhiByLiChun(), MonthGanZhi: lunar.GetMonthInGanZhi(), DayGanZhi: lunar.GetDayInGanZhi(),
		SuitableActivities:   stringsFromList(lunar.GetDayYiBySect(1)),
		UnsuitableActivities: stringsFromList(lunar.GetDayJiBySect(1)),
		Clashes:              []string{"冲" + lunar.GetDayChongDesc(), "煞" + lunar.GetDaySha()},
		PengZu:               []string{lunar.GetPengZuGan(), lunar.GetPengZuZhi()}, Hours: hours,
	}
}

func exportYear(year int) YearRecords {
	records := make([]DayRecord, 0, 366)
	// UTC is used only to enumerate Gregorian civil dates. No machine-local zone,
	// locale or current clock enters the exported lunar-go calculation.
	for date := time.Date(year, 1, 1, 0, 0, 0, 0, time.UTC); date.Year() == year; date = date.AddDate(0, 0, 1) {
		records = append(records, exportDay(year, int(date.Month()), date.Day()))
	}
	return YearRecords{SchemaVersion: schemaVersion, Year: year, Records: records}
}

func saveJSON(path string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0644)
}

func main() {
	start := flag.Int("start-year", 1901, "first Gregorian year (inclusive)")
	end := flag.Int("end-year", 2099, "last Gregorian year (inclusive)")
	output := flag.String("out", "generated/raw", "directory for uncompressed annual JSON")
	flag.Parse()
	if *start < 1901 || *end > 2099 || *start > *end {
		panic("export range must be within 1901–2099")
	}
	if err := os.MkdirAll(*output, 0755); err != nil {
		panic(err)
	}
	total := 0
	for year := *start; year <= *end; year++ {
		records := exportYear(year)
		path := filepath.Join(*output, fmt.Sprintf("%d.json", year))
		if err := saveJSON(path, records); err != nil {
			panic(err)
		}
		total += len(records.Records)
		fmt.Printf("%d: %d dates\n", year, len(records.Records))
	}
	fmt.Printf("Exported %d dates in %d annual files\n", total, *end-*start+1)
}
