(ns rv
  (:require
   [reagent.core :as r]
   [reagent.dom :as rdom]
   [react :as react]
   [goog.crypt :as crypt]
   [goog.crypt.Pkcs7]
   [goog.crypt.Md5]
   [clojure.string :as str]
   [shadow.resource :as rc]
   ["./helpers" :as helpers]
   ["bignumber.js" :as bn]
   ["starknet/provider" :refer [Provider]]
   ["starknet/utils/number" :refer [toBN toHex toFelt]]
   ["starknet/utils/hash" :refer [pedersen  computeHashOnElements]]
   ["starknet/utils/shortString" :refer [encodeShortString decodeShortString]]
   ["@starknet-react/core" :refer
    [StarknetProvider
     getInstalledInjectedConnectors
     useConnectors
     useContract
     useStarknetInvoke
     useStarknetCall
     useStarknet]])
  (:import [goog.crypt Sha256 Hmac Aes Cbc Md5]))

(declare use-cipher str->encoded-short-str init jhnn-provider)

;; prompt hash 0x57696c6c207468697320776f726b206e6f773f

(defonce rv-addr "0x114d7f9dc9af007b409876a38193ee4fd13ea5791f2837e7a36aec6b7cc6254")

(defonce rv-abi (rc/inline "abis/response.json"))

(defn use-rv []
  (useContract #js {:abi (aget (js/JSON.parse rv-abi) "abi") 
                    :address rv-addr}))

(defn mutate! []
  (set! js/window.starknet.provider jhnn-provider)
  (set! js/window.starknet.account.baseUrl jhnn-provider.baseUrl)
  (set! js/window.starknet.account.feederGatewayUrl jhnn-provider.feederGatewayUrl)
  (set! js/window.starknet.account.gatewayUrl jhnn-provider.gatewayUrl)
  (println "mutated!"))

(defn connect []
  (let [connectors-js (->> (useConnectors)
                           )
        connect (aget connectors-js "connect")
        connectors (aget connectors-js "connectors")]

    (println connectors-js)
    [:<>
     (for [connector connectors]
       [:button
        {:key (.id connector)
         :on-click (fn []
                     (connect connector)
                     (js/setTimeout mutate! 2000)
                     )}
        (str "Connect " (.name connector))])]))


;; (defn use-submit-prompt [rv-contract-js]
;;   let [contract (some-> rv-contract-js
;;                          (aget "contract"))
;;        contract-call-cypher-js (useStarknetCall #js {:contract contract
;;                                                       :method ""
;;                                                      :args #js []} )])

(defn prompt-contract []
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        [text set-text] (react/useState "")
        account (some-> starknet-js
                        (aget "account")
                        )
        invoke-submit-prompt (useStarknetInvoke #js {:contract contract :method
                                                     "submit_prompt"})
        [reset error submit-prompt! data loading]
        (mapv #(some->  invoke-submit-prompt
                       (aget %1))
              ["reset" "error" "invoke" "data" "loading"])

        ]
    (when account
      (if (or data error)
        [:div
         [:b (or data error)]
         [:button {:on-click #((reset))} "reset"]]
        (if loading
          [:i loading]
          [:div
           [:textarea {:name "texty"
                       :value text
                       :on-change    #(set-text (.. % -target -value))
                       :on-key-press (fn [e]
                                       (when (= (.-charCode e) 13)
                                         (.preventDefault e)
                                         (set-text "")))
                       :cols "40"
                       :rows "5"}]
           [:button {:on-click (fn [e]
                                 (let [partitioned-strings (re-seq #".{1,31}" text)
                                       prompt-as-encoded-strings (->> partitioned-strings
                                                                      (map encodeShortString)
                                                            )
                                       prompt-h (->> prompt-as-encoded-strings
                                                     (reduce (fn [acc el]
                                                               
                                                               (pedersen #js [acc el]
                                                                         ))
                                                             ))]
                                   (println prompt-h)
                                  (-> (submit-prompt! #js {:args #js [prompt-h (clj->js prompt-as-encoded-strings)
                                                              ]})
                                      ))
                                 )}
            (str "submit-prompt!" data)]])))))

(defn maybe-deprefix [supposed-hex]
  (if (clojure.string/starts-with? "0x" supposed-hex)
    (clojure.string/replace-first supposed-hex
                                  #"0x"
                                  "")
    supposed-hex))

(defn encoded-short-str->str [%string]
  (let [string (maybe-deprefix %string)
        by-two (re-seq #".{2}" string)]
    (reduce #(->> (js/parseInt %2 16)
                  (js/String.fromCharCode )
                  (str %1 ))
            ""
          by-two)
    ))

(defn view-prompts []
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )
        call-get-prompt (useStarknetCall #js {:contract contract :method
                                                   "get_prompt"
                                              :args #js ["0x4c6966653f"]})
        
        [prompt-js error]
        (mapv #(some->  call-get-prompt
                       (aget %1))
              ["data" "error" ])
        response (some->>
                  prompt-js
                  array-seq
                  first
                  
                  )
        response-to-display (if (zero? response)
                              response
                              (->> response
                               (map (comp decodeShortString toHex) )
                               (apply str)))]
    [:b (or
         error
         response-to-display
         )]))

(defn greeter []
  (let [starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )]
    (when account
      [:h4  (str "gm " (->> account
                            (take 5)
                            (apply str)))])))

(defn ^:export test-connectors []
  )

(def ^:export jhnn-provider (Provider. #js {:baseUrl "http://127.0.0.1:5050" }))

(defn simple-example []
  (let [injected-connectors (getInstalledInjectedConnectors)
        ]

    (if-not (seq (array-seq injected-connectors))
      (do
        (js/setTimeout init 1000))
      (do
        ;; (set! js/window.starknet_braavos.provider jhnn-provider)
        )
      )
    
   [(r/adapt-react-class StarknetProvider)
    {:connectors injected-connectors
     :defaultProvider jhnn-provider
     }
    [:f> greeter]
    [:f> connect]
    ;; [:f> greeter]

    [:f> prompt-contract]
    [:f> view-prompts]
    ;; [clock]
    ;; [color-input]
    ]))

(defn  init []
  (rdom/render [simple-example] (js/document.getElementById "app")))





