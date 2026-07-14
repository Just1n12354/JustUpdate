using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

// System.Windows.Shapes.Path kollidiert mit System.IO.Path - nur Rectangle wird
// hier gebraucht.
using Rectangle = System.Windows.Shapes.Rectangle;

namespace JustUpdate.Ui;

/// <summary>
/// Vollstaendige Versions-Historie im App-Stil: Versionsliste links, pro Version
/// eine Karte rechts. Das Markdown aus CHANGELOG.md wird in WPF-Elemente
/// uebersetzt (Aufzaehlungen, Zitate, **fett**, `code`) - so wie in v1.
///
/// Quelle: erst ein CHANGELOG.md neben der EXE, sonst GitHub raw. Beim Kunden
/// liegt normalerweise nur die EXE, also ist der Online-Weg der Normalfall.
/// </summary>
public partial class ChangelogFenster : Window
{
    private const string ChangelogUrl =
        "https://raw.githubusercontent.com/Just1n12354/JustUpdate/main/CHANGELOG.md";

    private static readonly Regex AbschnittKopf = new(@"^\s*##\s+(.+?)\s*$", RegexOptions.Compiled);
    private static readonly Regex TitelMitDatum = new(@"^(.+?)\s*\((.+?)\)\s*$", RegexOptions.Compiled);
    private static readonly Regex Aufzaehlung = new(@"^[-*]\s+(.+)$", RegexOptions.Compiled);
    private static readonly Regex Nummeriert = new(@"^(\d+)\.\s+(.+)$", RegexOptions.Compiled);
    private static readonly Regex Zitat = new(@"^>\s+(.+)$", RegexOptions.Compiled);
    private static readonly Regex Zwischentitel = new(@"^\*\*(.+?)\*\*\s*$", RegexOptions.Compiled);
    private static readonly Regex FettOderCode = new(@"\*\*(.+?)\*\*|`([^`]+)`", RegexOptions.Compiled);

    private static readonly Brush Hell = Pinsel("#ededf2");
    private static readonly Brush Fliesstext = Pinsel("#b9c0cc");
    private static readonly Brush Gedimmt = Pinsel("#8888a0");
    private static readonly Brush Akzent = Pinsel("#A3243B");
    private static readonly Brush CodeFarbe = Pinsel("#ffc090");
    private static readonly Brush Rahmen = Pinsel("#2a2a35");
    private static readonly Brush Kartenrand = Pinsel("#18181f");
    private static readonly Brush Pille = Pinsel("#25252f");

    public ChangelogFenster()
    {
        InitializeComponent();

        xUnterzeile.Text = "wird geladen ...";
        xQuelle.Text =
            $"Installiert: v{SelbstAktualisierung.EigeneVersion.ToString(3)}  —  " +
            "Quelle: github.com/Just1n12354/JustUpdate";

        Loaded += async (_, _) => await Laden();
    }

    private static Brush Pinsel(string hex)
    {
        var pinsel = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        pinsel.Freeze();
        return pinsel;
    }

    private async Task Laden()
    {
        string? text = LokalLesen() ?? await OnlineLesen();

        if (text is null)
        {
            xUnterzeile.Text = "nicht verfügbar";

            xInhalt.Children.Add(new TextBlock
            {
                Text = "Die Patch-Notes konnten nicht geladen werden.\n\n" +
                       "Es liegt kein CHANGELOG.md neben dem Programm und GitHub ist " +
                       "nicht erreichbar.",
                Foreground = Fliesstext,
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap
            });

            return;
        }

        Abschnitt[] abschnitte = Zerlegen(text);

        foreach (Abschnitt abschnitt in abschnitte)
        {
            Border karte = KarteBauen(abschnitt, out bool istAktuell);

            xInhalt.Children.Add(karte);
            xVersionsliste.Children.Add(ListeneintragBauen(abschnitt.Version, karte, istAktuell));
        }

        xUnterzeile.Text = abschnitte.Length == 1
            ? "1 Version"
            : $"{abschnitte.Length} Versionen";
    }

    private static string? LokalLesen()
    {
        try
        {
            string? ordner = Path.GetDirectoryName(Environment.ProcessPath);

            if (ordner is null)
            {
                return null;
            }

            string pfad = Path.Combine(ordner, "CHANGELOG.md");

            if (File.Exists(pfad))
            {
                string text = File.ReadAllText(pfad);

                if (text.Length > 50)
                {
                    return text;
                }
            }
        }
        catch (Exception)
        {
            // Kein lokales Changelog - dann eben online.
        }

        return null;
    }

    private static async Task<string?> OnlineLesen()
    {
        try
        {
            using var klient = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };

            klient.DefaultRequestHeaders.UserAgent.Add(
                new ProductInfoHeaderValue(
                    "JustUpdate",
                    SelbstAktualisierung.EigeneVersion.ToString(3)));

            return await klient.GetStringAsync(ChangelogUrl);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private sealed record Abschnitt(string Version, string Datum, string[] Zeilen);

    private static Abschnitt[] Zerlegen(string text)
    {
        var abschnitte = new List<Abschnitt>();

        string? titel = null;
        var zeilen = new List<string>();

        void Abschliessen()
        {
            if (titel is null)
            {
                return;
            }

            Match m = TitelMitDatum.Match(titel);

            string version = m.Success ? m.Groups[1].Value.Trim() : titel;
            string datum = m.Success ? m.Groups[2].Value.Trim() : string.Empty;

            abschnitte.Add(new Abschnitt(version, datum, [.. zeilen]));
        }

        foreach (string zeile in text.Split('\n'))
        {
            string ohneCr = zeile.TrimEnd('\r');
            Match kopf = AbschnittKopf.Match(ohneCr);

            if (kopf.Success)
            {
                Abschliessen();

                titel = kopf.Groups[1].Value.Trim();
                zeilen = [];
            }
            else if (titel is not null)
            {
                zeilen.Add(ohneCr);
            }
        }

        Abschliessen();

        return [.. abschnitte];
    }

    private Border KarteBauen(Abschnitt abschnitt, out bool istAktuell)
    {
        string eigene = "v" + SelbstAktualisierung.EigeneVersion.ToString(3);

        istAktuell = string.Equals(
            abschnitt.Version.TrimStart('v', 'V'),
            eigene.TrimStart('v'),
            StringComparison.OrdinalIgnoreCase);

        var inhalt = new StackPanel();

        // Kopfzeile: Version, Datums-Pille, AKTUELL-Abzeichen
        var kopf = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 8)
        };

        kopf.Children.Add(new TextBlock
        {
            Text = abschnitt.Version,
            FontSize = 17,
            FontWeight = FontWeights.Bold,
            Foreground = Hell,
            VerticalAlignment = VerticalAlignment.Center
        });

        if (abschnitt.Datum.Length > 0)
        {
            kopf.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(6),
                Background = Pille,
                Padding = new Thickness(8, 2, 8, 3),
                Margin = new Thickness(12, 3, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock
                {
                    Text = abschnitt.Datum,
                    FontSize = 11,
                    FontFamily = new FontFamily("Consolas"),
                    Foreground = Fliesstext
                }
            });
        }

        if (istAktuell)
        {
            kopf.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(8),
                Background = Akzent,
                Padding = new Thickness(8, 2, 8, 3),
                Margin = new Thickness(10, 2, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock
                {
                    Text = "AKTUELL",
                    FontSize = 9.5,
                    FontWeight = FontWeights.Bold,
                    Foreground = Brushes.White
                }
            });
        }

        inhalt.Children.Add(kopf);

        inhalt.Children.Add(new Rectangle
        {
            Height = 1,
            Fill = Rahmen,
            Margin = new Thickness(0, 0, 0, 10)
        });

        foreach (string zeile in abschnitt.Zeilen)
        {
            UIElement? element = ZeileBauen(zeile);

            if (element is not null)
            {
                inhalt.Children.Add(element);
            }
        }

        return new Border
        {
            CornerRadius = new CornerRadius(12),
            Background = Kartenrand,
            BorderBrush = Rahmen,
            BorderThickness = new Thickness(1),
            Padding = new Thickness(18, 14, 18, 16),
            Margin = new Thickness(0, 0, 0, 14),
            Child = inhalt
        };
    }

    private static UIElement? ZeileBauen(string zeile)
    {
        string kurz = zeile.Trim();

        if (kurz.Length == 0)
        {
            return null;
        }

        int einzug = zeile.Length - zeile.TrimStart().Length;

        Match aufzaehlung = Aufzaehlung.Match(kurz);

        if (aufzaehlung.Success)
        {
            return PunktZeile(
                "•",
                aufzaehlung.Groups[1].Value,
                einzug >= 2 ? 36 : 14,
                14);
        }

        Match nummeriert = Nummeriert.Match(kurz);

        if (nummeriert.Success)
        {
            return PunktZeile(
                nummeriert.Groups[1].Value + ".",
                nummeriert.Groups[2].Value,
                einzug >= 2 ? 36 : 14,
                20);
        }

        Match zitat = Zitat.Match(kurz);

        if (zitat.Success)
        {
            return new Border
            {
                BorderBrush = Akzent,
                BorderThickness = new Thickness(3, 0, 0, 0),
                Background = new SolidColorBrush(Color.FromArgb(0x33, 0xA3, 0x24, 0x3B)),
                Padding = new Thickness(10, 4, 6, 4),
                Margin = new Thickness(0, 6, 0, 6),
                Child = Text(zitat.Groups[1].Value, kursiv: true)
            };
        }

        Match zwischentitel = Zwischentitel.Match(kurz);

        if (zwischentitel.Success)
        {
            return Text(zwischentitel.Groups[1].Value, zwischentitel: true);
        }

        return Text(kurz);
    }

    private static Grid PunktZeile(string zeichen, string text, int links, int spaltenbreite)
    {
        var zeile = new Grid { Margin = new Thickness(links, 2, 0, 2) };

        zeile.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(spaltenbreite) });
        zeile.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var punkt = new TextBlock
        {
            Text = zeichen,
            Foreground = Akzent,
            FontSize = zeichen == "•" ? 14 : 12,
            FontWeight = FontWeights.Bold,
            VerticalAlignment = VerticalAlignment.Top
        };

        Grid.SetColumn(punkt, 0);
        zeile.Children.Add(punkt);

        TextBlock inhalt = Text(text);
        Grid.SetColumn(inhalt, 1);
        zeile.Children.Add(inhalt);

        return zeile;
    }

    /// <summary>
    /// Uebersetzt eine Markdown-Zeile in einen TextBlock. **fett** wird hell und
    /// fett, `code` wird Consolas und orange - sonst laesst sich ein Changelog
    /// mit vielen Dateinamen und Schaltern nicht lesen.
    /// </summary>
    private static TextBlock Text(string text, bool zwischentitel = false, bool kursiv = false)
    {
        var block = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            FontSize = zwischentitel ? 13 : 12,
            LineHeight = 18,
            Margin = zwischentitel
                ? new Thickness(0, 10, 0, 4)
                : new Thickness(0, 3, 0, 3),
            Foreground = zwischentitel ? Hell : kursiv ? Gedimmt : Fliesstext,
            FontWeight = zwischentitel ? FontWeights.SemiBold : FontWeights.Normal,
            FontStyle = kursiv ? FontStyles.Italic : FontStyles.Normal
        };

        int position = 0;

        foreach (Match treffer in FettOderCode.Matches(text))
        {
            if (treffer.Index > position)
            {
                block.Inlines.Add(new Run(text[position..treffer.Index]));
            }

            if (treffer.Groups[1].Success)
            {
                block.Inlines.Add(new Run(treffer.Groups[1].Value)
                {
                    FontWeight = FontWeights.Bold,
                    Foreground = Hell
                });
            }
            else
            {
                block.Inlines.Add(new Run(treffer.Groups[2].Value)
                {
                    FontFamily = new FontFamily("Consolas"),
                    FontSize = 11.5,
                    Foreground = CodeFarbe
                });
            }

            position = treffer.Index + treffer.Length;
        }

        if (position < text.Length)
        {
            block.Inlines.Add(new Run(text[position..]));
        }

        return block;
    }

    private Button ListeneintragBauen(string version, Border karte, bool istAktuell)
    {
        var knopf = new Button
        {
            Content = version,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(10, 7, 8, 7),
            Margin = new Thickness(0, 1, 0, 1),
            FontSize = 11.5,
            Cursor = Cursors.Hand,
            BorderThickness = new Thickness(0),
            Background = istAktuell ? Akzent : Brushes.Transparent,
            Foreground = istAktuell ? Brushes.White : Fliesstext,
            FontWeight = istAktuell ? FontWeights.SemiBold : FontWeights.Normal,
            Tag = karte
        };

        // Ohne eigenes Template legt WPF den Standard-Grauton darueber.
        var vorlage = new ControlTemplate(typeof(Button));
        var rahmen = new FrameworkElementFactory(typeof(Border));
        rahmen.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        rahmen.SetBinding(Border.BackgroundProperty,
            new System.Windows.Data.Binding(nameof(Button.Background))
            {
                RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent
            });

        var inhalt = new FrameworkElementFactory(typeof(ContentPresenter));
        inhalt.SetValue(MarginProperty, new Thickness(10, 7, 8, 7));
        rahmen.AppendChild(inhalt);

        vorlage.VisualTree = rahmen;
        knopf.Template = vorlage;

        knopf.Click += (_, _) => karte.BringIntoView();

        return knopf;
    }

    private void Gezogen(object sender, MouseButtonEventArgs e) => DragMove();

    private void Schliessen(object sender, RoutedEventArgs e) => Close();
}
