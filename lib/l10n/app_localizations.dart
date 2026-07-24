import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get appName;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeTitle;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languagePersian.
  ///
  /// In en, this message translates to:
  /// **'فارسی'**
  String get languagePersian;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Design beautifully, in any language'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Create stories, posts, covers, and text-based designs with ready-made templates.'**
  String get onboardingWelcomeTagline;

  /// No description provided for @onboardingWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Persian-first design — stories, posts, and typographic art from ready-made templates.'**
  String get onboardingWelcomeSubtitle;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'What do you create most?'**
  String get onboardingGoalTitle;

  /// No description provided for @onboardingGoalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a few options so we can show better templates.'**
  String get onboardingGoalSubtitle;

  /// No description provided for @onboardingGoalInstagram.
  ///
  /// In en, this message translates to:
  /// **'Instagram Stories'**
  String get onboardingGoalInstagram;

  /// No description provided for @onboardingGoalYoutube.
  ///
  /// In en, this message translates to:
  /// **'YouTube Thumbnails'**
  String get onboardingGoalYoutube;

  /// No description provided for @onboardingGoalPoetry.
  ///
  /// In en, this message translates to:
  /// **'Poetry & Quotes'**
  String get onboardingGoalPoetry;

  /// No description provided for @onboardingGoalPoster.
  ///
  /// In en, this message translates to:
  /// **'Posts & Ads'**
  String get onboardingGoalPoster;

  /// No description provided for @onboardingGoalTextOnPhoto.
  ///
  /// In en, this message translates to:
  /// **'Text on photo'**
  String get onboardingGoalTextOnPhoto;

  /// No description provided for @onboardingGoalBlankCanvas.
  ///
  /// In en, this message translates to:
  /// **'Blank canvas'**
  String get onboardingGoalBlankCanvas;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// No description provided for @onboardingReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Templates are ready'**
  String get onboardingReadyTitle;

  /// No description provided for @onboardingReadySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start from a design, change the text, and export.'**
  String get onboardingReadySubtitle;

  /// No description provided for @onboardingReadyCta.
  ///
  /// In en, this message translates to:
  /// **'Start designing'**
  String get onboardingReadyCta;

  /// No description provided for @onboardingReadyGreetingDefault.
  ///
  /// In en, this message translates to:
  /// **'Welcome, creator'**
  String get onboardingReadyGreetingDefault;

  /// No description provided for @onboardingReadyGreetingStoryteller.
  ///
  /// In en, this message translates to:
  /// **'Welcome, storyteller'**
  String get onboardingReadyGreetingStoryteller;

  /// No description provided for @onboardingReadyGreetingCreator.
  ///
  /// In en, this message translates to:
  /// **'Welcome, video creator'**
  String get onboardingReadyGreetingCreator;

  /// No description provided for @onboardingReadyGreetingPoet.
  ///
  /// In en, this message translates to:
  /// **'Welcome, poet'**
  String get onboardingReadyGreetingPoet;

  /// No description provided for @onboardingReadyGreetingMarketer.
  ///
  /// In en, this message translates to:
  /// **'Welcome, marketer'**
  String get onboardingReadyGreetingMarketer;

  /// No description provided for @onboardingArtTypography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get onboardingArtTypography;

  /// No description provided for @onboardingArtPersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get onboardingArtPersian;

  /// No description provided for @onboardingArtStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get onboardingArtStory;

  /// No description provided for @onboardingArtTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get onboardingArtTemplate;

  /// No description provided for @onboardingArtPersianLetters.
  ///
  /// In en, this message translates to:
  /// **'Persian letters'**
  String get onboardingArtPersianLetters;

  /// No description provided for @onboardingArtReadyText.
  ///
  /// In en, this message translates to:
  /// **'Ready text'**
  String get onboardingArtReadyText;

  /// No description provided for @onboardingArtLayers.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get onboardingArtLayers;

  /// No description provided for @onboardingArtAlphabet.
  ///
  /// In en, this message translates to:
  /// **'Aa'**
  String get onboardingArtAlphabet;

  /// No description provided for @onboardingArtBeautiful.
  ///
  /// In en, this message translates to:
  /// **'Beautiful'**
  String get onboardingArtBeautiful;

  /// No description provided for @settingsContentLanguagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Content languages'**
  String get settingsContentLanguagesTitle;

  /// No description provided for @settingsEnabledCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Templates to show on Home'**
  String get settingsEnabledCategoriesTitle;

  /// No description provided for @settingsResetOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Reset onboarding'**
  String get settingsResetOnboarding;

  /// No description provided for @canvasInteractionSection.
  ///
  /// In en, this message translates to:
  /// **'Canvas Interaction'**
  String get canvasInteractionSection;

  /// No description provided for @enableCanvasPanTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable canvas pan'**
  String get enableCanvasPanTitle;

  /// No description provided for @enableCanvasPanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag the canvas to reposition it'**
  String get enableCanvasPanSubtitle;

  /// No description provided for @enableCanvasZoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable canvas zoom'**
  String get enableCanvasZoomTitle;

  /// No description provided for @enableCanvasZoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom in and out'**
  String get enableCanvasZoomSubtitle;

  /// No description provided for @enableCanvasRotationTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable canvas rotation'**
  String get enableCanvasRotationTitle;

  /// No description provided for @enableCanvasRotationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reserved for future two-finger rotate gesture'**
  String get enableCanvasRotationSubtitle;

  /// No description provided for @exportSection.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportSection;

  /// No description provided for @defaultExportQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Default export quality'**
  String get defaultExportQualityTitle;

  /// No description provided for @exportQualityOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get exportQualityOriginal;

  /// No description provided for @exportQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get exportQualityHigh;

  /// No description provided for @exportQualityUltra.
  ///
  /// In en, this message translates to:
  /// **'Ultra quality'**
  String get exportQualityUltra;

  /// No description provided for @editorSection.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorSection;

  /// No description provided for @snapToGuidesTitle.
  ///
  /// In en, this message translates to:
  /// **'Snap to guides'**
  String get snapToGuidesTitle;

  /// No description provided for @snapToGuidesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-align layers to nearby edges and centers'**
  String get snapToGuidesSubtitle;

  /// No description provided for @showSpacingGuidesTitle.
  ///
  /// In en, this message translates to:
  /// **'Show spacing guides'**
  String get showSpacingGuidesTitle;

  /// No description provided for @showSpacingGuidesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight equal gaps between layers while dragging'**
  String get showSpacingGuidesSubtitle;

  /// No description provided for @multiFingerUndoRedoTitle.
  ///
  /// In en, this message translates to:
  /// **'Multi-finger undo / redo'**
  String get multiFingerUndoRedoTitle;

  /// No description provided for @multiFingerUndoRedoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Two-finger tap to undo, three-finger tap to redo. Off by default — can conflict with pinch gestures.'**
  String get multiFingerUndoRedoSubtitle;

  /// No description provided for @rightHandedToolbarTitle.
  ///
  /// In en, this message translates to:
  /// **'Right-handed toolbar'**
  String get rightHandedToolbarTitle;

  /// No description provided for @rightHandedToolbarSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Aligns the bottom strip to the right edge so tools sit closer to your right thumb. Tool order stays the same — only placement changes.'**
  String get rightHandedToolbarSubtitle;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @openAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openAction;

  /// No description provided for @renameAction.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameAction;

  /// No description provided for @documentMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Document options'**
  String get documentMenuTooltip;

  /// No description provided for @unsavedBadge.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get unsavedBadge;

  /// No description provided for @resizeCanvasAction.
  ///
  /// In en, this message translates to:
  /// **'Resize canvas'**
  String get resizeCanvasAction;

  /// No description provided for @photoSlotTapToReplace.
  ///
  /// In en, this message translates to:
  /// **'Tap to add your photo'**
  String get photoSlotTapToReplace;

  /// No description provided for @duplicateAction.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateAction;

  /// No description provided for @flipHorizontalAction.
  ///
  /// In en, this message translates to:
  /// **'Flip horizontally'**
  String get flipHorizontalAction;

  /// No description provided for @flipVerticalAction.
  ///
  /// In en, this message translates to:
  /// **'Flip vertically'**
  String get flipVerticalAction;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @applyAction.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyAction;

  /// No description provided for @doneAction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneAction;

  /// No description provided for @shareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareAction;

  /// No description provided for @keepAction.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keepAction;

  /// No description provided for @removeAction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeAction;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @navHomeTab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHomeTab;

  /// No description provided for @navProjectsTab.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get navProjectsTab;

  /// No description provided for @homeBrandTitle.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get homeBrandTitle;

  /// No description provided for @homeWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'What shall we make today?'**
  String get homeWelcomeTitle;

  /// No description provided for @homeWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start from a template or craft something new.'**
  String get homeWelcomeSubtitle;

  /// No description provided for @homeHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Start with a template'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit the text and create a beautiful design.'**
  String get homeHeroSubtitle;

  /// No description provided for @homeChooseTemplateAction.
  ///
  /// In en, this message translates to:
  /// **'Choose template'**
  String get homeChooseTemplateAction;

  /// No description provided for @homeQuickActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Start quickly'**
  String get homeQuickActionsTitle;

  /// No description provided for @editPhotoCta.
  ///
  /// In en, this message translates to:
  /// **'Edit a photo'**
  String get editPhotoCta;

  /// No description provided for @editPhotoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open an image and start refining'**
  String get editPhotoSubtitle;

  /// No description provided for @blankCanvasCta.
  ///
  /// In en, this message translates to:
  /// **'Blank canvas'**
  String get blankCanvasCta;

  /// No description provided for @blankCanvasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a size and build from scratch'**
  String get blankCanvasSubtitle;

  /// No description provided for @homeTextOnPhotoCta.
  ///
  /// In en, this message translates to:
  /// **'Text on photo'**
  String get homeTextOnPhotoCta;

  /// No description provided for @homeTextOnPhotoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start with a designed type layout'**
  String get homeTextOnPhotoSubtitle;

  /// No description provided for @homeSuggestedTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get homeSuggestedTitle;

  /// No description provided for @homeRecentNewTile.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get homeRecentNewTile;

  /// No description provided for @recentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent work'**
  String get recentTitle;

  /// No description provided for @seeAllAction.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAllAction;

  /// No description provided for @recentProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent projects'**
  String get recentProjectsTitle;

  /// No description provided for @lastOpenedLabel.
  ///
  /// In en, this message translates to:
  /// **'Last opened'**
  String get lastOpenedLabel;

  /// No description provided for @emptyProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'No designs yet'**
  String get emptyProjectsTitle;

  /// No description provided for @emptyProjectsBody.
  ///
  /// In en, this message translates to:
  /// **'Start with a template or create a blank canvas.'**
  String get emptyProjectsBody;

  /// No description provided for @emptyProjectsCta.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get emptyProjectsCta;

  /// No description provided for @trySampleAction.
  ///
  /// In en, this message translates to:
  /// **'Try a sample'**
  String get trySampleAction;

  /// No description provided for @moreTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTooltip;

  /// No description provided for @moreOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsTooltip;

  /// No description provided for @collapseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapseTooltip;

  /// No description provided for @dismissPanelSemantics.
  ///
  /// In en, this message translates to:
  /// **'Dismiss panel'**
  String get dismissPanelSemantics;

  /// No description provided for @undoLastChangeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Undo last change'**
  String get undoLastChangeSemantics;

  /// No description provided for @closePanelSemantics.
  ///
  /// In en, this message translates to:
  /// **'Close panel'**
  String get closePanelSemantics;

  /// No description provided for @bringForwardAction.
  ///
  /// In en, this message translates to:
  /// **'Bring forward'**
  String get bringForwardAction;

  /// No description provided for @sendBackwardAction.
  ///
  /// In en, this message translates to:
  /// **'Send backward'**
  String get sendBackwardAction;

  /// No description provided for @lockAction.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lockAction;

  /// No description provided for @unlockAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockAction;

  /// No description provided for @lockLayerAction.
  ///
  /// In en, this message translates to:
  /// **'Lock layer'**
  String get lockLayerAction;

  /// No description provided for @unlockLayerAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock layer'**
  String get unlockLayerAction;

  /// No description provided for @hideAction.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideAction;

  /// No description provided for @showAction.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showAction;

  /// No description provided for @protectedBasePhotoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Protected base photo'**
  String get protectedBasePhotoTooltip;

  /// No description provided for @basePhotoLabel.
  ///
  /// In en, this message translates to:
  /// **'Base photo'**
  String get basePhotoLabel;

  /// No description provided for @lockedLabel.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get lockedLabel;

  /// No description provided for @hiddenLabel.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hiddenLabel;

  /// No description provided for @multiSelectCount.
  ///
  /// In en, this message translates to:
  /// **'Multi-select · {count}'**
  String multiSelectCount(int count);

  /// No description provided for @multiSelectExit.
  ///
  /// In en, this message translates to:
  /// **'Exit multi-select'**
  String get multiSelectExit;

  /// No description provided for @longPressCanvasMultiSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press canvas to select multiple layers.'**
  String get longPressCanvasMultiSelectHint;

  /// No description provided for @layerControlsSingleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{type}. Long-press canvas to multi-select.'**
  String layerControlsSingleSubtitle(String type);

  /// No description provided for @layerControlsMultiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Align or distribute the selected layers.'**
  String get layerControlsMultiSubtitle;

  /// No description provided for @layerControlsReviewLayersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review order and individual layer names.'**
  String get layerControlsReviewLayersSubtitle;

  /// No description provided for @renameLayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename layer'**
  String get renameLayerTitle;

  /// No description provided for @alignAction.
  ///
  /// In en, this message translates to:
  /// **'Align'**
  String get alignAction;

  /// No description provided for @alignToCanvasTitle.
  ///
  /// In en, this message translates to:
  /// **'Align to canvas'**
  String get alignToCanvasTitle;

  /// No description provided for @alignSelectedLayersTitle.
  ///
  /// In en, this message translates to:
  /// **'Align selected layers'**
  String get alignSelectedLayersTitle;

  /// No description provided for @alignToCanvasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Align this layer to the canvas.'**
  String get alignToCanvasSubtitle;

  /// No description provided for @alignSelectedLayersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Align selected layers to each other.'**
  String get alignSelectedLayersSubtitle;

  /// No description provided for @layersSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} layers selected'**
  String layersSelectedCount(int count);

  /// No description provided for @moveSelectedLayerInsideCanvas.
  ///
  /// In en, this message translates to:
  /// **'Move the selected layer inside the canvas.'**
  String get moveSelectedLayerInsideCanvas;

  /// No description provided for @alignHorizontalGroup.
  ///
  /// In en, this message translates to:
  /// **'Horizontal align'**
  String get alignHorizontalGroup;

  /// No description provided for @alignVerticalGroup.
  ///
  /// In en, this message translates to:
  /// **'Vertical align'**
  String get alignVerticalGroup;

  /// No description provided for @distributeGroup.
  ///
  /// In en, this message translates to:
  /// **'Distribute'**
  String get distributeGroup;

  /// No description provided for @horizontalOption.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get horizontalOption;

  /// No description provided for @verticalOption.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get verticalOption;

  /// No description provided for @alignLeftAction.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get alignLeftAction;

  /// No description provided for @alignCenterAction.
  ///
  /// In en, this message translates to:
  /// **'Align center'**
  String get alignCenterAction;

  /// No description provided for @alignRightAction.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get alignRightAction;

  /// No description provided for @alignTopAction.
  ///
  /// In en, this message translates to:
  /// **'Align top'**
  String get alignTopAction;

  /// No description provided for @alignMiddleAction.
  ///
  /// In en, this message translates to:
  /// **'Align middle'**
  String get alignMiddleAction;

  /// No description provided for @alignBottomAction.
  ///
  /// In en, this message translates to:
  /// **'Align bottom'**
  String get alignBottomAction;

  /// No description provided for @distributeHorizontallyAction.
  ///
  /// In en, this message translates to:
  /// **'Distribute horizontally'**
  String get distributeHorizontallyAction;

  /// No description provided for @distributeVerticallyAction.
  ///
  /// In en, this message translates to:
  /// **'Distribute vertically'**
  String get distributeVerticallyAction;

  /// No description provided for @selectThreeOrMoreLayersHint.
  ///
  /// In en, this message translates to:
  /// **'Select 3 or more layers.'**
  String get selectThreeOrMoreLayersHint;

  /// No description provided for @noLayersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No layers yet.\nAdd text, image or shape to begin.'**
  String get noLayersEmpty;

  /// No description provided for @removeBasePhotoCommand.
  ///
  /// In en, this message translates to:
  /// **'Remove base photo'**
  String get removeBasePhotoCommand;

  /// No description provided for @removeBasePhotoBody.
  ///
  /// In en, this message translates to:
  /// **'This is the photo your project was built from. Removing it turns this into a blank design project. You can undo this.'**
  String get removeBasePhotoBody;

  /// No description provided for @recentLabel.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentLabel;

  /// No description provided for @customLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customLabel;

  /// No description provided for @scaleLabel.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get scaleLabel;

  /// No description provided for @freeLabel.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freeLabel;

  /// No description provided for @projectNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameLabel;

  /// No description provided for @renameProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename project'**
  String get renameProjectTitle;

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get deleteProjectTitle;

  /// No description provided for @deleteProjectBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be permanently removed.'**
  String deleteProjectBody(String name);

  /// No description provided for @duplicatedProject.
  ///
  /// In en, this message translates to:
  /// **'Duplicated \"{name}\"'**
  String duplicatedProject(String name);

  /// No description provided for @renamedProject.
  ///
  /// In en, this message translates to:
  /// **'Renamed to \"{name}\"'**
  String renamedProject(String name);

  /// No description provided for @deletedProject.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\"'**
  String deletedProject(String name);

  /// No description provided for @openProjectSemantics.
  ///
  /// In en, this message translates to:
  /// **'Open {name}, last edited {time}'**
  String openProjectSemantics(String name, String time);

  /// No description provided for @openTemplateSemantics.
  ///
  /// In en, this message translates to:
  /// **'Open template {name}'**
  String openTemplateSemantics(String name);

  /// No description provided for @createCustomAction.
  ///
  /// In en, this message translates to:
  /// **'Create custom'**
  String get createCustomAction;

  /// No description provided for @widthLabel.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get widthLabel;

  /// No description provided for @heightLabel.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get heightLabel;

  /// No description provided for @widthPxLabel.
  ///
  /// In en, this message translates to:
  /// **'Width (px)'**
  String get widthPxLabel;

  /// No description provided for @heightPxLabel.
  ///
  /// In en, this message translates to:
  /// **'Height (px)'**
  String get heightPxLabel;

  /// No description provided for @newDesignTitle.
  ///
  /// In en, this message translates to:
  /// **'New design'**
  String get newDesignTitle;

  /// No description provided for @newDesignName.
  ///
  /// In en, this message translates to:
  /// **'New design'**
  String get newDesignName;

  /// No description provided for @newDocumentReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a new document?'**
  String get newDocumentReplaceTitle;

  /// No description provided for @newDocumentReplaceUnsavedBody.
  ///
  /// In en, this message translates to:
  /// **'Your current unsaved work will be discarded.'**
  String get newDocumentReplaceUnsavedBody;

  /// No description provided for @recoveredDraftName.
  ///
  /// In en, this message translates to:
  /// **'Recovered draft'**
  String get recoveredDraftName;

  /// No description provided for @basePhotoPinnedToBack.
  ///
  /// In en, this message translates to:
  /// **'The base photo always stays at the back.'**
  String get basePhotoPinnedToBack;

  /// No description provided for @importedImageName.
  ///
  /// In en, this message translates to:
  /// **'Imported image'**
  String get importedImageName;

  /// No description provided for @importPhotoCommand.
  ///
  /// In en, this message translates to:
  /// **'Import photo'**
  String get importPhotoCommand;

  /// No description provided for @sampleName.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get sampleName;

  /// No description provided for @sampleCommand.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get sampleCommand;

  /// No description provided for @pickCanvasSizeBody.
  ///
  /// In en, this message translates to:
  /// **'Pick a canvas size to start with.'**
  String get pickCanvasSizeBody;

  /// No description provided for @resizeCanvasBody.
  ///
  /// In en, this message translates to:
  /// **'Layers keep their position. The canvas resizes from the top-left corner.'**
  String get resizeCanvasBody;

  /// No description provided for @squareGroup.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get squareGroup;

  /// No description provided for @portraitGroup.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get portraitGroup;

  /// No description provided for @landscapeGroup.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get landscapeGroup;

  /// No description provided for @storyGroup.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get storyGroup;

  /// No description provided for @printGroup.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printGroup;

  /// No description provided for @customGroup.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customGroup;

  /// No description provided for @instagramPostPreset.
  ///
  /// In en, this message translates to:
  /// **'Instagram Post'**
  String get instagramPostPreset;

  /// No description provided for @squarePreset.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get squarePreset;

  /// No description provided for @square2048Preset.
  ///
  /// In en, this message translates to:
  /// **'Square 2048'**
  String get square2048Preset;

  /// No description provided for @portrait45Preset.
  ///
  /// In en, this message translates to:
  /// **'Portrait 4:5'**
  String get portrait45Preset;

  /// No description provided for @youtubeThumbnailPreset.
  ///
  /// In en, this message translates to:
  /// **'YouTube Thumbnail'**
  String get youtubeThumbnailPreset;

  /// No description provided for @linkedInPostPreset.
  ///
  /// In en, this message translates to:
  /// **'LinkedIn Post'**
  String get linkedInPostPreset;

  /// No description provided for @twitterPostPreset.
  ///
  /// In en, this message translates to:
  /// **'Twitter Post (16:9)'**
  String get twitterPostPreset;

  /// No description provided for @facebookCoverPreset.
  ///
  /// In en, this message translates to:
  /// **'Facebook Cover'**
  String get facebookCoverPreset;

  /// No description provided for @hd1080pPreset.
  ///
  /// In en, this message translates to:
  /// **'HD 1080p'**
  String get hd1080pPreset;

  /// No description provided for @storyPreset.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get storyPreset;

  /// No description provided for @instagramStory916Preset.
  ///
  /// In en, this message translates to:
  /// **'Instagram Story (9:16)'**
  String get instagramStory916Preset;

  /// No description provided for @a4Portrait300Preset.
  ///
  /// In en, this message translates to:
  /// **'A4 Portrait (300 dpi)'**
  String get a4Portrait300Preset;

  /// No description provided for @a4Landscape300Preset.
  ///
  /// In en, this message translates to:
  /// **'A4 Landscape (300 dpi)'**
  String get a4Landscape300Preset;

  /// No description provided for @customSizeValidation.
  ///
  /// In en, this message translates to:
  /// **'Width & height must be 16–16384.'**
  String get customSizeValidation;

  /// No description provided for @enterImageUrlValidation.
  ///
  /// In en, this message translates to:
  /// **'Enter an image URL.'**
  String get enterImageUrlValidation;

  /// No description provided for @imageUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Image URL'**
  String get imageUrlLabel;

  /// No description provided for @imageSizingHint.
  ///
  /// In en, this message translates to:
  /// **'Canvas will be sized to the image’s intrinsic dimensions and the image will be added as a layer.'**
  String get imageSizingHint;

  /// No description provided for @noProjectsYet.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noProjectsYet;

  /// No description provided for @startByCreatingOne.
  ///
  /// In en, this message translates to:
  /// **'Start by creating one'**
  String get startByCreatingOne;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgo(int count);

  /// No description provided for @weeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}w ago'**
  String weeksAgo(int count);

  /// No description provided for @monthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}mo ago'**
  String monthsAgo(int count);

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templatesTitle;

  /// No description provided for @templatesBrowseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find templates by language and category.'**
  String get templatesBrowseSubtitle;

  /// No description provided for @templatesBrowseCategorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a template and start designing.'**
  String get templatesBrowseCategorySubtitle;

  /// No description provided for @templatesCategoryFilterAction.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get templatesCategoryFilterAction;

  /// No description provided for @templatesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search templates'**
  String get templatesSearchHint;

  /// No description provided for @templatesLanguageFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get templatesLanguageFilterLabel;

  /// No description provided for @templatesCategoryChipStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get templatesCategoryChipStories;

  /// No description provided for @templatesCategoryChipAds.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get templatesCategoryChipAds;

  /// No description provided for @templatesCategoryChipThumbnails.
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get templatesCategoryChipThumbnails;

  /// No description provided for @templatesCategoryChipQuotes.
  ///
  /// In en, this message translates to:
  /// **'Quotes'**
  String get templatesCategoryChipQuotes;

  /// No description provided for @templatesCategoryChipText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get templatesCategoryChipText;

  /// No description provided for @homeTemplateLanguageAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get homeTemplateLanguageAll;

  /// No description provided for @homeTemplateLanguagePersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get homeTemplateLanguagePersian;

  /// No description provided for @homeTemplateLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get homeTemplateLanguageEnglish;

  /// No description provided for @homeTemplateLanguageMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get homeTemplateLanguageMixed;

  /// No description provided for @homeTemplatesRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended to start'**
  String get homeTemplatesRecommended;

  /// No description provided for @homeTemplatesInstagramStories.
  ///
  /// In en, this message translates to:
  /// **'Instagram stories'**
  String get homeTemplatesInstagramStories;

  /// No description provided for @homeTemplatesTextTypography.
  ///
  /// In en, this message translates to:
  /// **'Text and typography'**
  String get homeTemplatesTextTypography;

  /// No description provided for @homeTemplatesAdvertisingPosts.
  ///
  /// In en, this message translates to:
  /// **'Advertising posts'**
  String get homeTemplatesAdvertisingPosts;

  /// No description provided for @homeTemplatesYoutubeThumbnails.
  ///
  /// In en, this message translates to:
  /// **'YouTube thumbnails'**
  String get homeTemplatesYoutubeThumbnails;

  /// No description provided for @homeTemplatesQuotesPoems.
  ///
  /// In en, this message translates to:
  /// **'Quotes and poems'**
  String get homeTemplatesQuotesPoems;

  /// No description provided for @allFilter.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allFilter;

  /// No description provided for @noTemplatesFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'No templates found'**
  String get noTemplatesFoundTitle;

  /// No description provided for @noTemplatesFoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try changing filters or view all templates.'**
  String get noTemplatesFoundSubtitle;

  /// No description provided for @noTemplatesInCategory.
  ///
  /// In en, this message translates to:
  /// **'No templates in this category yet.'**
  String get noTemplatesInCategory;

  /// No description provided for @categoryInstagramStory.
  ///
  /// In en, this message translates to:
  /// **'Instagram Story'**
  String get categoryInstagramStory;

  /// No description provided for @categoryYoutubeThumbnail.
  ///
  /// In en, this message translates to:
  /// **'YouTube Thumbnail'**
  String get categoryYoutubeThumbnail;

  /// No description provided for @categoryPoetryPost.
  ///
  /// In en, this message translates to:
  /// **'Poetry Post'**
  String get categoryPoetryPost;

  /// No description provided for @categoryPromotionalPoster.
  ///
  /// In en, this message translates to:
  /// **'Promotional Poster'**
  String get categoryPromotionalPoster;

  /// No description provided for @categorySocial.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get categorySocial;

  /// No description provided for @categoryStory.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get categoryStory;

  /// No description provided for @categoryQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get categoryQuote;

  /// No description provided for @categorySale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get categorySale;

  /// No description provided for @categoryGreeting.
  ///
  /// In en, this message translates to:
  /// **'Greeting'**
  String get categoryGreeting;

  /// No description provided for @categoryBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get categoryBusiness;

  /// No description provided for @categoryEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get categoryEvent;

  /// No description provided for @categoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get categoryFood;

  /// No description provided for @categoryMotivational.
  ///
  /// In en, this message translates to:
  /// **'Motivation'**
  String get categoryMotivational;

  /// No description provided for @templateLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get templateLanguageEnglish;

  /// No description provided for @templateLanguagePersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get templateLanguagePersian;

  /// No description provided for @editorSaveProject.
  ///
  /// In en, this message translates to:
  /// **'Save project'**
  String get editorSaveProject;

  /// No description provided for @editorExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get editorExport;

  /// No description provided for @editorFitToScreen.
  ///
  /// In en, this message translates to:
  /// **'Fit to screen'**
  String get editorFitToScreen;

  /// No description provided for @editorNewDocument.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get editorNewDocument;

  /// No description provided for @centerSelectedLayerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Center selected layer in canvas'**
  String get centerSelectedLayerTooltip;

  /// No description provided for @centerLayerCommand.
  ///
  /// In en, this message translates to:
  /// **'Center layer'**
  String get centerLayerCommand;

  /// No description provided for @layersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get layersTooltip;

  /// No description provided for @undoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoTooltip;

  /// No description provided for @redoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redoTooltip;

  /// No description provided for @photoTool.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photoTool;

  /// No description provided for @textTool.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textTool;

  /// No description provided for @stickerTool.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get stickerTool;

  /// No description provided for @shapeTool.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get shapeTool;

  /// No description provided for @drawTool.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get drawTool;

  /// No description provided for @cropTool.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropTool;

  /// No description provided for @canvasTool.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get canvasTool;

  /// No description provided for @addTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addTextTitle;

  /// No description provided for @galleryAction.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryAction;

  /// No description provided for @cameraAction.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraAction;

  /// No description provided for @replaceShapeTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace shape'**
  String get replaceShapeTitle;

  /// No description provided for @replaceShapeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a new shape — colours and size are kept.'**
  String get replaceShapeSubtitle;

  /// No description provided for @addShapeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add shape'**
  String get addShapeTitle;

  /// No description provided for @addShapeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a shape — you can restyle it after.'**
  String get addShapeSubtitle;

  /// No description provided for @shapeSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get shapeSectionBasic;

  /// No description provided for @shapeSectionBubbles.
  ///
  /// In en, this message translates to:
  /// **'Bubbles'**
  String get shapeSectionBubbles;

  /// No description provided for @shapeSectionSymbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get shapeSectionSymbols;

  /// No description provided for @shapeSectionLinesArrows.
  ///
  /// In en, this message translates to:
  /// **'Lines & Arrows'**
  String get shapeSectionLinesArrows;

  /// No description provided for @shapeKindRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get shapeKindRectangle;

  /// No description provided for @shapeKindRoundedRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get shapeKindRoundedRectangle;

  /// No description provided for @shapeKindOval.
  ///
  /// In en, this message translates to:
  /// **'Oval'**
  String get shapeKindOval;

  /// No description provided for @shapeKindTriangle.
  ///
  /// In en, this message translates to:
  /// **'Triangle'**
  String get shapeKindTriangle;

  /// No description provided for @shapeKindDiamond.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get shapeKindDiamond;

  /// No description provided for @shapeKindHexagon.
  ///
  /// In en, this message translates to:
  /// **'Hexagon'**
  String get shapeKindHexagon;

  /// No description provided for @shapeKindSpeechBubble.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get shapeKindSpeechBubble;

  /// No description provided for @shapeKindQuoteBubble.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get shapeKindQuoteBubble;

  /// No description provided for @shapeKindPlus.
  ///
  /// In en, this message translates to:
  /// **'Plus'**
  String get shapeKindPlus;

  /// No description provided for @shapeKindCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get shapeKindCheck;

  /// No description provided for @shapeKindCross.
  ///
  /// In en, this message translates to:
  /// **'Cross'**
  String get shapeKindCross;

  /// No description provided for @shapeKindLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get shapeKindLine;

  /// No description provided for @shapeKindArrowRight.
  ///
  /// In en, this message translates to:
  /// **'Arrow right'**
  String get shapeKindArrowRight;

  /// No description provided for @shapeKindArrowLeft.
  ///
  /// In en, this message translates to:
  /// **'Arrow left'**
  String get shapeKindArrowLeft;

  /// No description provided for @shapeKindArrowUp.
  ///
  /// In en, this message translates to:
  /// **'Arrow up'**
  String get shapeKindArrowUp;

  /// No description provided for @shapeKindArrowDown.
  ///
  /// In en, this message translates to:
  /// **'Arrow down'**
  String get shapeKindArrowDown;

  /// No description provided for @addPhotoAction.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhotoAction;

  /// No description provided for @importPhotoToAction.
  ///
  /// In en, this message translates to:
  /// **'Import a photo to {action}.'**
  String importPhotoToAction(String action);

  /// No description provided for @pickImageToAction.
  ///
  /// In en, this message translates to:
  /// **'Pick an image to {action}'**
  String pickImageToAction(String action);

  /// No description provided for @cropActionVerb.
  ///
  /// In en, this message translates to:
  /// **'crop'**
  String get cropActionVerb;

  /// No description provided for @savedProject.
  ///
  /// In en, this message translates to:
  /// **'Saved “{name}”'**
  String savedProject(String name);

  /// No description provided for @imageLayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Image {index}'**
  String imageLayerTitle(int index);

  /// No description provided for @shareUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Sharing is unavailable on this device.'**
  String get shareUnavailableMessage;

  /// No description provided for @newDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get newDocumentTitle;

  /// No description provided for @presetTab.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get presetTab;

  /// No description provided for @customTab.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customTab;

  /// No description provided for @imageTab.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageTab;

  /// No description provided for @removeBasePhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove base photo?'**
  String get removeBasePhotoTitle;

  /// No description provided for @resizeBehaviorTitle.
  ///
  /// In en, this message translates to:
  /// **'Resize behavior'**
  String get resizeBehaviorTitle;

  /// No description provided for @resizeBehaviorScaleSemantics.
  ///
  /// In en, this message translates to:
  /// **'Resize behavior: Scale shape (tap for Free)'**
  String get resizeBehaviorScaleSemantics;

  /// No description provided for @resizeBehaviorFreeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Resize behavior: Resize freely (tap for Scale)'**
  String get resizeBehaviorFreeSemantics;

  /// No description provided for @resizeBehaviorScaleObjectSemantics.
  ///
  /// In en, this message translates to:
  /// **'Resize behavior: Scale object (tap for Free)'**
  String get resizeBehaviorScaleObjectSemantics;

  /// No description provided for @strokeSizeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Stroke size'**
  String get strokeSizeSemantics;

  /// No description provided for @styleTool.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get styleTool;

  /// No description provided for @lookTool.
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get lookTool;

  /// No description provided for @lookActionVerb.
  ///
  /// In en, this message translates to:
  /// **'restyle'**
  String get lookActionVerb;

  /// No description provided for @sizeTool.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sizeTool;

  /// No description provided for @sizeIncreaseAction.
  ///
  /// In en, this message translates to:
  /// **'Increase size'**
  String get sizeIncreaseAction;

  /// No description provided for @sizeDecreaseAction.
  ///
  /// In en, this message translates to:
  /// **'Decrease size'**
  String get sizeDecreaseAction;

  /// No description provided for @borderTool.
  ///
  /// In en, this message translates to:
  /// **'Border'**
  String get borderTool;

  /// No description provided for @shadowTool.
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get shadowTool;

  /// No description provided for @effectsTool.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get effectsTool;

  /// No description provided for @replaceTool.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replaceTool;

  /// No description provided for @replaceImageAction.
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get replaceImageAction;

  /// No description provided for @relinkImageAction.
  ///
  /// In en, this message translates to:
  /// **'Relink image'**
  String get relinkImageAction;

  /// No description provided for @imageUnavailableLabel.
  ///
  /// In en, this message translates to:
  /// **'Image unavailable'**
  String get imageUnavailableLabel;

  /// No description provided for @backgroundTool.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get backgroundTool;

  /// No description provided for @colorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get colorLabel;

  /// No description provided for @fillLabel.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get fillLabel;

  /// No description provided for @fontTool.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get fontTool;

  /// No description provided for @stylesTool.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get stylesTool;

  /// No description provided for @layoutTool.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get layoutTool;

  /// No description provided for @resizeTool.
  ///
  /// In en, this message translates to:
  /// **'Resize'**
  String get resizeTool;

  /// No description provided for @bgShortLabel.
  ///
  /// In en, this message translates to:
  /// **'BG'**
  String get bgShortLabel;

  /// No description provided for @textColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get textColorTitle;

  /// No description provided for @fontSizeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSizeSemantics;

  /// No description provided for @moreActionsSemantics.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActionsSemantics;

  /// No description provided for @editTextAction.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get editTextAction;

  /// No description provided for @boldAction.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get boldAction;

  /// No description provided for @italicAction.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italicAction;

  /// No description provided for @underlineAction.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underlineAction;

  /// No description provided for @scaleTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Scale text'**
  String get scaleTextTitle;

  /// No description provided for @scaleTextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Corner drag scales the whole text uniformly. Box always fits the text.'**
  String get scaleTextSubtitle;

  /// No description provided for @resizeBoxTitle.
  ///
  /// In en, this message translates to:
  /// **'Resize box'**
  String get resizeBoxTitle;

  /// No description provided for @resizeBoxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Corner drag changes the wrap width. Font size stays the same; height auto-fits.'**
  String get resizeBoxSubtitle;

  /// No description provided for @scaleTextSummary.
  ///
  /// In en, this message translates to:
  /// **'Scale text — corner drag scales the whole text'**
  String get scaleTextSummary;

  /// No description provided for @resizeBoxSummary.
  ///
  /// In en, this message translates to:
  /// **'Resize box — corner drag changes the wrap width'**
  String get resizeBoxSummary;

  /// No description provided for @textDirectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Text direction'**
  String get textDirectionTitle;

  /// No description provided for @textDirectionAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto direction'**
  String get textDirectionAutoTitle;

  /// No description provided for @textDirectionRtlTitle.
  ///
  /// In en, this message translates to:
  /// **'Right to left'**
  String get textDirectionRtlTitle;

  /// No description provided for @textDirectionLtrTitle.
  ///
  /// In en, this message translates to:
  /// **'Left to right'**
  String get textDirectionLtrTitle;

  /// No description provided for @typeSomethingHint.
  ///
  /// In en, this message translates to:
  /// **'Type something…'**
  String get typeSomethingHint;

  /// No description provided for @colorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get colorsLabel;

  /// No description provided for @moreColorsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More colors'**
  String get moreColorsTooltip;

  /// No description provided for @hueLabel.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hueLabel;

  /// No description provided for @opacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacityLabel;

  /// No description provided for @fillOpacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Fill opacity'**
  String get fillOpacityLabel;

  /// No description provided for @strokeOpacityLabel.
  ///
  /// In en, this message translates to:
  /// **'Stroke opacity'**
  String get strokeOpacityLabel;

  /// No description provided for @stylePresetClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get stylePresetClassic;

  /// No description provided for @stylePresetQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get stylePresetQuote;

  /// No description provided for @stylePresetHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get stylePresetHighlight;

  /// No description provided for @stylePresetShadowSoft.
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get stylePresetShadowSoft;

  /// No description provided for @stylePresetContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get stylePresetContrast;

  /// No description provided for @stylePresetGlass.
  ///
  /// In en, this message translates to:
  /// **'Glass'**
  String get stylePresetGlass;

  /// No description provided for @stylePresetCaption.
  ///
  /// In en, this message translates to:
  /// **'Caption'**
  String get stylePresetCaption;

  /// No description provided for @stylePresetSubtitleBand.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get stylePresetSubtitleBand;

  /// No description provided for @stylePresetCta.
  ///
  /// In en, this message translates to:
  /// **'CTA'**
  String get stylePresetCta;

  /// No description provided for @stylePresetBadgeRed.
  ///
  /// In en, this message translates to:
  /// **'Badge'**
  String get stylePresetBadgeRed;

  /// No description provided for @stylePresetHashtag.
  ///
  /// In en, this message translates to:
  /// **'Hashtag'**
  String get stylePresetHashtag;

  /// No description provided for @stylePresetOutline.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get stylePresetOutline;

  /// No description provided for @stylePresetNeon.
  ///
  /// In en, this message translates to:
  /// **'Neon'**
  String get stylePresetNeon;

  /// No description provided for @stylePresetPoster.
  ///
  /// In en, this message translates to:
  /// **'Poster'**
  String get stylePresetPoster;

  /// No description provided for @stylePresetSticker.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get stylePresetSticker;

  /// No description provided for @stylePresetPop3d.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get stylePresetPop3d;

  /// No description provided for @effectStrokeLabel.
  ///
  /// In en, this message translates to:
  /// **'Stroke'**
  String get effectStrokeLabel;

  /// No description provided for @effectGradientLabel.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get effectGradientLabel;

  /// No description provided for @distanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get distanceLabel;

  /// No description provided for @blurLabel.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get blurLabel;

  /// No description provided for @thicknessLabel.
  ///
  /// In en, this message translates to:
  /// **'Thickness'**
  String get thicknessLabel;

  /// No description provided for @fillColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Fill color'**
  String get fillColorTitle;

  /// No description provided for @shadowColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Shadow color'**
  String get shadowColorTitle;

  /// Accessibility label for the 2D shadow offset pad — dragging the dot sets shadow direction and distance together.
  ///
  /// In en, this message translates to:
  /// **'Shadow direction and distance'**
  String get shadowOffsetPadSemantics;

  /// Accessibility label for the floating quick-capsule shown above any selected layer.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActionsSemantics;

  /// Accessibility label for the floating quick-capsule shown above a selected text layer.
  ///
  /// In en, this message translates to:
  /// **'Text quick actions'**
  String get textQuickActionsSemantics;

  /// Title of the numeric-entry dialog opened by tapping the size panel's value chip.
  ///
  /// In en, this message translates to:
  /// **'Exact size'**
  String get exactSizeTitle;

  /// No description provided for @blurDirectionOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Blur, direction, opacity'**
  String get blurDirectionOpacitySubtitle;

  /// No description provided for @backgroundColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Background color'**
  String get backgroundColorTitle;

  /// No description provided for @borderColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Border color'**
  String get borderColorTitle;

  /// No description provided for @shapeLabel.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get shapeLabel;

  /// No description provided for @styleLabel.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get styleLabel;

  /// No description provided for @directionLabel.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get directionLabel;

  /// No description provided for @behaviorLabel.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get behaviorLabel;

  /// No description provided for @noneOption.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noneOption;

  /// No description provided for @pillOption.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get pillOption;

  /// No description provided for @cardOption.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get cardOption;

  /// No description provided for @tagOption.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tagOption;

  /// No description provided for @sharpOption.
  ///
  /// In en, this message translates to:
  /// **'Sharp'**
  String get sharpOption;

  /// No description provided for @hairlineOption.
  ///
  /// In en, this message translates to:
  /// **'Hairline'**
  String get hairlineOption;

  /// No description provided for @solidOption.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get solidOption;

  /// No description provided for @angleLabel.
  ///
  /// In en, this message translates to:
  /// **'Angle'**
  String get angleLabel;

  /// No description provided for @softOption.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get softOption;

  /// No description provided for @hardOption.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get hardOption;

  /// No description provided for @glowOption.
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get glowOption;

  /// No description provided for @liftOption.
  ///
  /// In en, this message translates to:
  /// **'Lift'**
  String get liftOption;

  /// No description provided for @reflowBoxTitle.
  ///
  /// In en, this message translates to:
  /// **'Reflow box'**
  String get reflowBoxTitle;

  /// No description provided for @cornerDragScalesTextHint.
  ///
  /// In en, this message translates to:
  /// **'Corner drag scales text'**
  String get cornerDragScalesTextHint;

  /// No description provided for @cornerDragWrapWidthHint.
  ///
  /// In en, this message translates to:
  /// **'Corner drag changes wrap width'**
  String get cornerDragWrapWidthHint;

  /// No description provided for @lineHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Line height'**
  String get lineHeightLabel;

  /// No description provided for @letterSpacingLabel.
  ///
  /// In en, this message translates to:
  /// **'Letter spacing'**
  String get letterSpacingLabel;

  /// No description provided for @tightOption.
  ///
  /// In en, this message translates to:
  /// **'Tight'**
  String get tightOption;

  /// No description provided for @normalOption.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normalOption;

  /// No description provided for @relaxedOption.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get relaxedOption;

  /// No description provided for @looseOption.
  ///
  /// In en, this message translates to:
  /// **'Loose'**
  String get looseOption;

  /// No description provided for @wideOption.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get wideOption;

  /// No description provided for @roundnessLabel.
  ///
  /// In en, this message translates to:
  /// **'Roundness'**
  String get roundnessLabel;

  /// No description provided for @verticalPaddingLabel.
  ///
  /// In en, this message translates to:
  /// **'Vertical padding'**
  String get verticalPaddingLabel;

  /// No description provided for @horizontalPaddingLabel.
  ///
  /// In en, this message translates to:
  /// **'Horizontal padding'**
  String get horizontalPaddingLabel;

  /// No description provided for @hidePreciseControls.
  ///
  /// In en, this message translates to:
  /// **'Hide precise controls'**
  String get hidePreciseControls;

  /// No description provided for @adjustPrecisely.
  ///
  /// In en, this message translates to:
  /// **'Adjust precisely'**
  String get adjustPrecisely;

  /// No description provided for @systemDefaultFont.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefaultFont;

  /// No description provided for @allFontsTitle.
  ///
  /// In en, this message translates to:
  /// **'All fonts'**
  String get allFontsTitle;

  /// No description provided for @recommendedFontsLabel.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommendedFontsLabel;

  /// No description provided for @presetsLabel.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presetsLabel;

  /// No description provided for @fontScriptEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get fontScriptEnglish;

  /// No description provided for @fontScriptPersian.
  ///
  /// In en, this message translates to:
  /// **'فارسی'**
  String get fontScriptPersian;

  /// No description provided for @fontCategorySans.
  ///
  /// In en, this message translates to:
  /// **'Sans'**
  String get fontCategorySans;

  /// No description provided for @fontCategoryModern.
  ///
  /// In en, this message translates to:
  /// **'Modern'**
  String get fontCategoryModern;

  /// No description provided for @fontCategoryDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get fontCategoryDisplay;

  /// No description provided for @fontCategoryScript.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get fontCategoryScript;

  /// No description provided for @fontCategoryMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get fontCategoryMono;

  /// No description provided for @fontCategoryTraditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional'**
  String get fontCategoryTraditional;

  /// No description provided for @fontCategoryNastaliq.
  ///
  /// In en, this message translates to:
  /// **'Nastaliq'**
  String get fontCategoryNastaliq;

  /// No description provided for @hexLabel.
  ///
  /// In en, this message translates to:
  /// **'Hex'**
  String get hexLabel;

  /// No description provided for @eyedropperTooltip.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper'**
  String get eyedropperTooltip;

  /// No description provided for @copyColorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy color code'**
  String get copyColorTooltip;

  /// No description provided for @toolLabel.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get toolLabel;

  /// No description provided for @chooseToolTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a tool'**
  String get chooseToolTitle;

  /// No description provided for @thinOption.
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get thinOption;

  /// No description provided for @mediumOption.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get mediumOption;

  /// No description provided for @thickOption.
  ///
  /// In en, this message translates to:
  /// **'Thick'**
  String get thickOption;

  /// No description provided for @heavyOption.
  ///
  /// In en, this message translates to:
  /// **'Heavy'**
  String get heavyOption;

  /// No description provided for @lightOption.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightOption;

  /// No description provided for @strongOption.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strongOption;

  /// No description provided for @offOption.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get offOption;

  /// No description provided for @onOption.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get onOption;

  /// No description provided for @sidesTool.
  ///
  /// In en, this message translates to:
  /// **'Sides'**
  String get sidesTool;

  /// No description provided for @sidesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sides'**
  String sidesCount(int count);

  /// No description provided for @drawGroup.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get drawGroup;

  /// No description provided for @shapesGroup.
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get shapesGroup;

  /// No description provided for @effectsGroup.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get effectsGroup;

  /// No description provided for @penTool.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get penTool;

  /// No description provided for @lineTool.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get lineTool;

  /// No description provided for @arrowTool.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get arrowTool;

  /// No description provided for @dashedOption.
  ///
  /// In en, this message translates to:
  /// **'Dashed'**
  String get dashedOption;

  /// No description provided for @dottedOption.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get dottedOption;

  /// No description provided for @dashDotOption.
  ///
  /// In en, this message translates to:
  /// **'Dash dot'**
  String get dashDotOption;

  /// No description provided for @eraserTool.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get eraserTool;

  /// No description provided for @squareLabel.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get squareLabel;

  /// No description provided for @circleLabel.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get circleLabel;

  /// No description provided for @hexagonLabel.
  ///
  /// In en, this message translates to:
  /// **'Hexagon'**
  String get hexagonLabel;

  /// No description provided for @polygonLabel.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get polygonLabel;

  /// No description provided for @strokeColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Stroke color'**
  String get strokeColorTitle;

  /// No description provided for @strokeWidthLabel.
  ///
  /// In en, this message translates to:
  /// **'Stroke width'**
  String get strokeWidthLabel;

  /// No description provided for @noFillOption.
  ///
  /// In en, this message translates to:
  /// **'No fill'**
  String get noFillOption;

  /// No description provided for @sameColorOption.
  ///
  /// In en, this message translates to:
  /// **'Same color'**
  String get sameColorOption;

  /// No description provided for @polygonSidesLabel.
  ///
  /// In en, this message translates to:
  /// **'Polygon sides'**
  String get polygonSidesLabel;

  /// No description provided for @cornerRadiusLabel.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get cornerRadiusLabel;

  /// No description provided for @brightnessLabel.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightnessLabel;

  /// No description provided for @contrastLabel.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrastLabel;

  /// No description provided for @saturationLabel.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturationLabel;

  /// No description provided for @exposureLabel.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get exposureLabel;

  /// No description provided for @warmthLabel.
  ///
  /// In en, this message translates to:
  /// **'Warmth'**
  String get warmthLabel;

  /// No description provided for @intensityLabel.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get intensityLabel;

  /// No description provided for @featherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get featherLabel;

  /// No description provided for @vignetteColorTitle.
  ///
  /// In en, this message translates to:
  /// **'Vignette color'**
  String get vignetteColorTitle;

  /// No description provided for @popOption.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get popOption;

  /// No description provided for @outlineOption.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineOption;

  /// No description provided for @chooseAnotherStickerAction.
  ///
  /// In en, this message translates to:
  /// **'Choose another sticker'**
  String get chooseAnotherStickerAction;

  /// No description provided for @stickersTitle.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get stickersTitle;

  /// No description provided for @searchEmojisHint.
  ///
  /// In en, this message translates to:
  /// **'Search emojis'**
  String get searchEmojisHint;

  /// No description provided for @noRecentStickersYet.
  ///
  /// In en, this message translates to:
  /// **'No recent stickers yet'**
  String get noRecentStickersYet;

  /// No description provided for @recentStickersHint.
  ///
  /// In en, this message translates to:
  /// **'Your recently used stickers will appear here.'**
  String get recentStickersHint;

  /// No description provided for @warmOption.
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get warmOption;

  /// No description provided for @coolOption.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get coolOption;

  /// No description provided for @monoOption.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get monoOption;

  /// No description provided for @fadeOption.
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get fadeOption;

  /// No description provided for @vintageOption.
  ///
  /// In en, this message translates to:
  /// **'Vintage'**
  String get vintageOption;

  /// No description provided for @dramaOption.
  ///
  /// In en, this message translates to:
  /// **'Drama'**
  String get dramaOption;

  /// No description provided for @vignetteLabel.
  ///
  /// In en, this message translates to:
  /// **'Vignette'**
  String get vignetteLabel;

  /// No description provided for @adjustPreciselySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Brightness, contrast, saturation, exposure, warmth'**
  String get adjustPreciselySubtitle;

  /// No description provided for @vignetteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Soft radial darkening from the centre'**
  String get vignetteSubtitle;

  /// No description provided for @noEffectsApplied.
  ///
  /// In en, this message translates to:
  /// **'No effects applied.'**
  String get noEffectsApplied;

  /// No description provided for @openLookToAddEffectHint.
  ///
  /// In en, this message translates to:
  /// **'Open Look to add one.'**
  String get openLookToAddEffectHint;

  /// No description provided for @selectiveMaskLabel.
  ///
  /// In en, this message translates to:
  /// **'Selective'**
  String get selectiveMaskLabel;

  /// No description provided for @selectiveMaskHint.
  ///
  /// In en, this message translates to:
  /// **'Limit the stack to a region of the layer'**
  String get selectiveMaskHint;

  /// No description provided for @maskPresetOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get maskPresetOff;

  /// No description provided for @maskPresetTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get maskPresetTop;

  /// No description provided for @maskPresetBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get maskPresetBottom;

  /// No description provided for @maskPresetCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get maskPresetCenter;

  /// No description provided for @maskPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get maskPresetCustom;

  /// No description provided for @adjustRegionAction.
  ///
  /// In en, this message translates to:
  /// **'Adjust region'**
  String get adjustRegionAction;

  /// No description provided for @maskShapeRect.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get maskShapeRect;

  /// No description provided for @maskShapeEllipse.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get maskShapeEllipse;

  /// No description provided for @maskFeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Feather'**
  String get maskFeatherLabel;

  /// No description provided for @maskInvertLabel.
  ///
  /// In en, this message translates to:
  /// **'Invert'**
  String get maskInvertLabel;

  /// No description provided for @resumeEditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Resume unsaved changes?'**
  String get resumeEditsTitle;

  /// No description provided for @resumeEditsBody.
  ///
  /// In en, this message translates to:
  /// **'This design closed before its latest changes were saved.'**
  String get resumeEditsBody;

  /// No description provided for @resumeDraftBanner.
  ///
  /// In en, this message translates to:
  /// **'You have an unsaved design from a previous session.'**
  String get resumeDraftBanner;

  /// No description provided for @resumeAction.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeAction;

  /// No description provided for @discardAction.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardAction;

  /// No description provided for @unknownEffectLabel.
  ///
  /// In en, this message translates to:
  /// **'Unknown effect ({type})'**
  String unknownEffectLabel(String type);

  /// No description provided for @inactiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactiveLabel;

  /// No description provided for @roundedOption.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get roundedOption;

  /// No description provided for @squircleOption.
  ///
  /// In en, this message translates to:
  /// **'Squircle'**
  String get squircleOption;

  /// No description provided for @starOption.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get starOption;

  /// No description provided for @heartOption.
  ///
  /// In en, this message translates to:
  /// **'Heart'**
  String get heartOption;

  /// No description provided for @canvasBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Canvas background'**
  String get canvasBackgroundTitle;

  /// No description provided for @transparentOption.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get transparentOption;

  /// No description provided for @photoBackgroundHint.
  ///
  /// In en, this message translates to:
  /// **'Background only shows behind transparent or uncovered areas of your photo.'**
  String get photoBackgroundHint;

  /// No description provided for @resetCropAction.
  ///
  /// In en, this message translates to:
  /// **'Reset crop'**
  String get resetCropAction;

  /// No description provided for @cropImageAction.
  ///
  /// In en, this message translates to:
  /// **'Crop image'**
  String get cropImageAction;

  /// No description provided for @restoreImageAction.
  ///
  /// In en, this message translates to:
  /// **'Restore image'**
  String get restoreImageAction;

  /// No description provided for @freeOption.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freeOption;

  /// No description provided for @exportDesignTitle.
  ///
  /// In en, this message translates to:
  /// **'Export design'**
  String get exportDesignTitle;

  /// No description provided for @previewExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview export'**
  String get previewExportTitle;

  /// No description provided for @canvasDimensions.
  ///
  /// In en, this message translates to:
  /// **'Canvas {width} × {height}'**
  String canvasDimensions(String width, String height);

  /// No description provided for @formatLabel.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get formatLabel;

  /// No description provided for @previewShareAction.
  ///
  /// In en, this message translates to:
  /// **'Preview & Share'**
  String get previewShareAction;

  /// No description provided for @previewSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Preview & Save'**
  String get previewSaveAction;

  /// No description provided for @savedToPhotoLibrary.
  ///
  /// In en, this message translates to:
  /// **'Saved to your photo library'**
  String get savedToPhotoLibrary;

  /// No description provided for @sharedMessage.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get sharedMessage;

  /// No description provided for @reducedResolutionWarning.
  ///
  /// In en, this message translates to:
  /// **'Exporting at reduced resolution to fit device memory.'**
  String get reducedResolutionWarning;

  /// No description provided for @qualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get qualityLabel;

  /// No description provided for @qualityPercent.
  ///
  /// In en, this message translates to:
  /// **'Quality {percent}%'**
  String qualityPercent(String percent);

  /// No description provided for @outputPixels.
  ///
  /// In en, this message translates to:
  /// **'Output: {width} × {height} px'**
  String outputPixels(String width, String height);

  /// No description provided for @matchesCanvasAspect.
  ///
  /// In en, this message translates to:
  /// **'Matches your canvas aspect.'**
  String get matchesCanvasAspect;

  /// No description provided for @letterboxExportHint.
  ///
  /// In en, this message translates to:
  /// **'Your design will be centred and the bands filled with the canvas background — never stretched.'**
  String get letterboxExportHint;

  /// No description provided for @customSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom size'**
  String get customSizeTitle;

  /// No description provided for @enterPositiveWholeNumbers.
  ///
  /// In en, this message translates to:
  /// **'Enter positive whole numbers.'**
  String get enterPositiveWholeNumbers;

  /// No description provided for @maximumDimensionEitherSide.
  ///
  /// In en, this message translates to:
  /// **'Maximum is {dimension} on either side.'**
  String maximumDimensionEitherSide(String dimension);

  /// No description provided for @useSizeAction.
  ///
  /// In en, this message translates to:
  /// **'Use size'**
  String get useSizeAction;

  /// No description provided for @customSizeChip.
  ///
  /// In en, this message translates to:
  /// **'Custom · {width}×{height}'**
  String customSizeChip(String width, String height);

  /// No description provided for @originalSizeQuality.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get originalSizeQuality;

  /// No description provided for @highQuality.
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get highQuality;

  /// No description provided for @ultraQuality.
  ///
  /// In en, this message translates to:
  /// **'Ultra quality'**
  String get ultraQuality;

  /// No description provided for @useCanvasSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use canvas size'**
  String get useCanvasSizeSubtitle;

  /// No description provided for @storyLabel.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get storyLabel;

  /// No description provided for @portraitLabel.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get portraitLabel;

  /// No description provided for @pickExactPixelsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick exact pixels'**
  String get pickExactPixelsSubtitle;

  /// No description provided for @designExportSubject.
  ///
  /// In en, this message translates to:
  /// **'Design export'**
  String get designExportSubject;

  /// No description provided for @originalOption.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get originalOption;

  /// No description provided for @circleOption.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get circleOption;

  /// No description provided for @widthSettingLabel.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get widthSettingLabel;

  /// No description provided for @shapePanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get shapePanelTitle;

  /// No description provided for @couldntOpenPhoto.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this photo. Try again or pick a different one.'**
  String get couldntOpenPhoto;

  /// No description provided for @couldntLoadProjects.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your projects. Pull down to retry.'**
  String get couldntLoadProjects;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get somethingWentWrong;

  /// No description provided for @journalWriteFailedWarning.
  ///
  /// In en, this message translates to:
  /// **'Low storage — crash recovery is off. Free some space and save your project.'**
  String get journalWriteFailedWarning;

  /// No description provided for @allowPhotoAccessSettings.
  ///
  /// In en, this message translates to:
  /// **'Allow photo access in Settings to continue.'**
  String get allowPhotoAccessSettings;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @documentHistoryAction.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get documentHistoryAction;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No edits yet'**
  String get historyEmpty;

  /// No description provided for @historyStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Document opened'**
  String get historyStartLabel;

  /// No description provided for @historyCurrentSemantic.
  ///
  /// In en, this message translates to:
  /// **'current step'**
  String get historyCurrentSemantic;

  /// No description provided for @historyUndoneSemantic.
  ///
  /// In en, this message translates to:
  /// **'undone'**
  String get historyUndoneSemantic;

  /// No description provided for @histAddText.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get histAddText;

  /// No description provided for @histAddImage.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get histAddImage;

  /// No description provided for @histAddShape.
  ///
  /// In en, this message translates to:
  /// **'Add shape'**
  String get histAddShape;

  /// No description provided for @histAddPaint.
  ///
  /// In en, this message translates to:
  /// **'Add drawing'**
  String get histAddPaint;

  /// No description provided for @histAddLayer.
  ///
  /// In en, this message translates to:
  /// **'Add layer'**
  String get histAddLayer;

  /// No description provided for @histRemoveLayer.
  ///
  /// In en, this message translates to:
  /// **'Delete layer'**
  String get histRemoveLayer;

  /// No description provided for @histRenameLayer.
  ///
  /// In en, this message translates to:
  /// **'Rename layer'**
  String get histRenameLayer;

  /// No description provided for @histReorderLayer.
  ///
  /// In en, this message translates to:
  /// **'Reorder layer'**
  String get histReorderLayer;

  /// No description provided for @histOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get histOpacity;

  /// No description provided for @histLock.
  ///
  /// In en, this message translates to:
  /// **'Lock layer'**
  String get histLock;

  /// No description provided for @histUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock layer'**
  String get histUnlock;

  /// No description provided for @histShow.
  ///
  /// In en, this message translates to:
  /// **'Show layer'**
  String get histShow;

  /// No description provided for @histHide.
  ///
  /// In en, this message translates to:
  /// **'Hide layer'**
  String get histHide;

  /// No description provided for @histMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get histMove;

  /// No description provided for @histResize.
  ///
  /// In en, this message translates to:
  /// **'Resize'**
  String get histResize;

  /// No description provided for @histRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get histRotate;

  /// No description provided for @histTransform.
  ///
  /// In en, this message translates to:
  /// **'Transform'**
  String get histTransform;

  /// No description provided for @histFlipH.
  ///
  /// In en, this message translates to:
  /// **'Flip horizontally'**
  String get histFlipH;

  /// No description provided for @histFlipV.
  ///
  /// In en, this message translates to:
  /// **'Flip vertically'**
  String get histFlipV;

  /// No description provided for @histCanvasBg.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get histCanvasBg;

  /// No description provided for @histCanvasBgMode.
  ///
  /// In en, this message translates to:
  /// **'Background mode'**
  String get histCanvasBgMode;

  /// No description provided for @histResizeCanvas.
  ///
  /// In en, this message translates to:
  /// **'Resize canvas'**
  String get histResizeCanvas;

  /// No description provided for @histEditText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get histEditText;

  /// No description provided for @histTextDirection.
  ///
  /// In en, this message translates to:
  /// **'Text direction'**
  String get histTextDirection;

  /// No description provided for @histTextResizeMode.
  ///
  /// In en, this message translates to:
  /// **'Text resize mode'**
  String get histTextResizeMode;

  /// No description provided for @histImageAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust image'**
  String get histImageAdjust;

  /// No description provided for @histImageBorder.
  ///
  /// In en, this message translates to:
  /// **'Image border'**
  String get histImageBorder;

  /// No description provided for @histImageCrop.
  ///
  /// In en, this message translates to:
  /// **'Crop image'**
  String get histImageCrop;

  /// No description provided for @histImageFilter.
  ///
  /// In en, this message translates to:
  /// **'Image filter'**
  String get histImageFilter;

  /// No description provided for @histImageFit.
  ///
  /// In en, this message translates to:
  /// **'Image fit'**
  String get histImageFit;

  /// No description provided for @histImageShadow.
  ///
  /// In en, this message translates to:
  /// **'Image shadow'**
  String get histImageShadow;

  /// No description provided for @histImageShape.
  ///
  /// In en, this message translates to:
  /// **'Image shape'**
  String get histImageShape;

  /// No description provided for @histReplaceImage.
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get histReplaceImage;

  /// No description provided for @histRestoreImage.
  ///
  /// In en, this message translates to:
  /// **'Restore image'**
  String get histRestoreImage;

  /// No description provided for @histPaintStyle.
  ///
  /// In en, this message translates to:
  /// **'Drawing style'**
  String get histPaintStyle;

  /// No description provided for @histPaintResize.
  ///
  /// In en, this message translates to:
  /// **'Drawing resize mode'**
  String get histPaintResize;

  /// No description provided for @histShapeFill.
  ///
  /// In en, this message translates to:
  /// **'Shape fill'**
  String get histShapeFill;

  /// No description provided for @histShapeStroke.
  ///
  /// In en, this message translates to:
  /// **'Shape stroke'**
  String get histShapeStroke;

  /// No description provided for @histShapeRadius.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get histShapeRadius;

  /// No description provided for @histShapeShadow.
  ///
  /// In en, this message translates to:
  /// **'Shape shadow'**
  String get histShapeShadow;

  /// No description provided for @histShapeResizeMode.
  ///
  /// In en, this message translates to:
  /// **'Shape resize mode'**
  String get histShapeResizeMode;

  /// No description provided for @histReplaceShape.
  ///
  /// In en, this message translates to:
  /// **'Replace shape'**
  String get histReplaceShape;

  /// No description provided for @histVignette.
  ///
  /// In en, this message translates to:
  /// **'Vignette'**
  String get histVignette;

  /// No description provided for @histEffectDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete effect'**
  String get histEffectDelete;

  /// No description provided for @histEffectReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder effect'**
  String get histEffectReorder;

  /// No description provided for @histEffectRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore effect'**
  String get histEffectRestore;

  /// No description provided for @histEffectToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle effect'**
  String get histEffectToggle;

  /// No description provided for @histBasePhotoSet.
  ///
  /// In en, this message translates to:
  /// **'Set base photo'**
  String get histBasePhotoSet;

  /// No description provided for @histBasePhotoClear.
  ///
  /// In en, this message translates to:
  /// **'Clear base photo'**
  String get histBasePhotoClear;

  /// No description provided for @histProjectPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo project'**
  String get histProjectPhoto;

  /// No description provided for @histProjectDesign.
  ///
  /// In en, this message translates to:
  /// **'Design project'**
  String get histProjectDesign;

  /// No description provided for @histCombinedEdit.
  ///
  /// In en, this message translates to:
  /// **'Combined edit'**
  String get histCombinedEdit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
